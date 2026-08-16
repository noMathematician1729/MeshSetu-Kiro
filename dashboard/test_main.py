import unittest

from fastapi.testclient import TestClient

from main import app, latest


class DashboardTest(unittest.TestCase):
    def setUp(self):
        latest.clear()
        self.client = TestClient(app)

    def test_auth_and_partial_event_updates(self):
        self.assertEqual(
            self.client.post(
                "/api/events", json={"event_id": "e1"}
            ).status_code,
            401,
        )
        headers = {"x-meshsetu-demo-key": "change-me"}
        self.assertEqual(
            self.client.post(
                "/api/events",
                headers=headers,
                json={
                    "event_id": "e1",
                    "priority": "p0Critical",
                    "incident_type": "medical",
                    "transcript": "help",
                },
            ).status_code,
            200,
        )
        self.assertEqual(
            self.client.post(
                "/api/events",
                headers=headers,
                json={
                    "event_id": "e1",
                    "voice_clip_id": "clip-1",
                    "audio_state": "complete",
                },
            ).status_code,
            200,
        )
        event = self.client.get("/api/events").json()[0]
        self.assertEqual(event["transcript"], "help")
        self.assertEqual(event["audio_state"], "complete")


if __name__ == "__main__":
    unittest.main()
