import unittest
import json
from pathlib import Path

from app.data.body_graph import (
    BODY_GRAPH,
    CONCERN_RISK_BUMP,
    find_connection,
    get_node,
)


class TestBodyGraph(unittest.TestCase):
    def setUp(self):
        kb_path = Path(__file__).resolve().parent.parent / "app" / "data" / "anatomy_kb.json"
        with open(kb_path, "r", encoding="utf-8") as f:
            kb_data = json.load(f)
        self.kb_regions = {entry["region"] for entry in kb_data["regions"]}

    def test_all_kb_regions_in_body_graph(self):
        graph_regions = set(BODY_GRAPH.keys())
        missing = self.kb_regions - graph_regions
        self.assertEqual(len(missing), 0, f"Missing regions in BODY_GRAPH: {missing}")
        self.assertEqual(len(BODY_GRAPH), 34)

    def test_graph_connections_are_reciprocal(self):
        for region_a, node in BODY_GRAPH.items():
            self.assertIn("system", node)
            self.assertIn("connects_to", node)
            for conn in node["connects_to"]:
                target_region = conn["region"]
                self.assertIn(
                    target_region,
                    BODY_GRAPH,
                    f"Target region '{target_region}' connected from '{region_a}' does not exist in graph",
                )
                self.assertIn(conn["concern"], CONCERN_RISK_BUMP)
                # Check reciprocity
                reciprocal_conn = find_connection(target_region, region_a)
                self.assertIsNotNone(
                    reciprocal_conn,
                    f"Connection from '{region_a}' to '{target_region}' is not reciprocal!",
                )

    def test_find_connection_existing_and_non_existing(self):
        # Cardiac radiation to left arm
        conn = find_connection("Chest / Heart", "Left Arm / Shoulder")
        self.assertIsNotNone(conn)
        self.assertEqual(conn["concern"], "high")
        self.assertIn("left arm", conn["note"].lower())

        # Sciatica pattern
        conn_sciatica = find_connection("Back Pain (Lower)", "Right Leg / Knee")
        self.assertIsNotNone(conn_sciatica)
        self.assertEqual(conn_sciatica["concern"], "low")

        # Unconnected regions
        self.assertIsNone(find_connection("Headache / Cranial", "Left Foot"))
        self.assertIsNone(find_connection("Unknown Region", "Neck"))

    def test_get_node(self):
        node = get_node("Neck")
        self.assertIsNotNone(node)
        self.assertEqual(node["system"], "musculoskeletal")


if __name__ == "__main__":
    unittest.main()
