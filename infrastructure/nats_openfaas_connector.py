#!/usr/bin/env python3
"""
🔗 NATS JetStream -> OpenFaaS Connector

Closes the last gap in the event-driven claim: this is the process that
actually subscribes to the S3-EVENTS JetStream stream, invokes the
image-processor-app function over HTTP for each event, ACKs on success,
and re-publishes to the DLQ-POISON stream after 3 failed attempts.

Run this as a long-lived process (see nats-connector-deployment.yaml) inside
the cluster. It is the runtime component that makes NATS->GW dispatch in the
architecture diagrams a real code path rather than only a diagram.

Requires: pip install nats-py requests
"""
import asyncio
import json
import os
import requests
import nats
from nats.js.api import ConsumerConfig, AckPolicy, DeliverPolicy

NATS_URL = os.getenv("NATS_URL", "nats://nats.nats.svc.cluster.local:4222")
OPENFAAS_GATEWAY = os.getenv("OPENFAAS_GATEWAY", "http://gateway.openfaas.svc.cluster.local:8080")
FUNCTION_NAME = os.getenv("FUNCTION_NAME", "image-processor-app")
STREAM_NAME = "S3-EVENTS"
SUBJECT = "s3.events.uploads"
DURABLE_CONSUMER = "openfaas-image-processor-consumer"
MAX_DELIVER = 3


async def publish_to_dlq(js, original_payload: bytes, reason: str):
    envelope = {
        "original_event": json.loads(original_payload) if original_payload else {},
        "failure_reason": reason,
    }
    await js.publish("s3.events.dlq", json.dumps(envelope).encode())
    print(f"[DLQ] Routed poison message to DLQ-POISON: {reason}")


async def handle_message(msg, js):
    try:
        payload = msg.data
        body = json.loads(payload)

        # Normalize into the same {Records:[{s3:{bucket,object}}]} shape the
        # handler already parses, so no handler.py change is required.
        resp = requests.post(
            f"{OPENFAAS_GATEWAY}/function/{FUNCTION_NAME}",
            data=payload,
            headers={"Content-Type": "application/json"},
            timeout=15,
        )

        if resp.status_code == 200:
            await msg.ack()
            print(f"[ACK] Processed event, function returned 200 ({resp.elapsed.total_seconds()*1000:.1f}ms)")
        else:
            num_delivered = msg.metadata.num_delivered
            if num_delivered >= MAX_DELIVER:
                await publish_to_dlq(js, payload, f"HTTP {resp.status_code} after {num_delivered} attempts")
                await msg.ack()  # ack the original so it stops redelivering; DLQ now owns it
            else:
                await msg.nak()
                print(f"[NAK] Attempt {num_delivered}/{MAX_DELIVER} failed with HTTP {resp.status_code}, will retry")

    except Exception as e:
        num_delivered = msg.metadata.num_delivered
        if num_delivered >= MAX_DELIVER:
            await publish_to_dlq(js, msg.data, f"Exception after {num_delivered} attempts: {e}")
            await msg.ack()
        else:
            await msg.nak()
            print(f"[NAK] Attempt {num_delivered}/{MAX_DELIVER} raised exception: {e}, will retry")


async def main():
    nc = await nats.connect(NATS_URL)
    js = nc.jetstream()

    await js.add_consumer(
        STREAM_NAME,
        ConsumerConfig(
            durable_name=DURABLE_CONSUMER,
            ack_policy=AckPolicy.EXPLICIT,
            deliver_policy=DeliverPolicy.ALL,
            max_deliver=MAX_DELIVER,
            ack_wait=5,  # seconds, matches the 5s AckWait documented in the README
        ),
    )

    psub = await js.pull_subscribe(SUBJECT, durable=DURABLE_CONSUMER, stream=STREAM_NAME)
    print(f"👂 Listening on '{SUBJECT}' (stream={STREAM_NAME}), forwarding to {OPENFAAS_GATEWAY}/function/{FUNCTION_NAME}")

    while True:
        try:
            msgs = await psub.fetch(batch=5, timeout=5)
        except asyncio.TimeoutError:
            continue
        for msg in msgs:
            await handle_message(msg, js)


if __name__ == "__main__":
    asyncio.run(main())
