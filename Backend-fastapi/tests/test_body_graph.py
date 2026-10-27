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

    def test_find_connection_is_one_hop_only(self):
        """Pins the honesty claim in the module docstring: this is adjacency, not
        inference. A two-hop pair must not be reachable through find_connection,
        or every "1-hop lookup" statement about the graph would be false and any
        report of it as multi-hop reasoning would be unearned.

        Headache connects to Neck; Neck connects to Left Shoulder. So the pair
        (Headache, Left Shoulder) is exactly two hops apart and must return None -
        the function reads one adjacency list, it does not walk the graph.
        """
        self.assertIsNotNone(find_connection("Headache / Cranial", "Neck"))
        self.assertIsNotNone(find_connection("Neck", "Left Shoulder"))
        self.assertIsNone(find_connection("Headache / Cranial", "Left Shoulder"))

    def test_no_region_lists_itself_as_a_connection(self):
        # A self-edge would make the one-hop bump fire on a region against
        # itself in any co-report, inflating the score for no clinical reason.
        for region_a, node in BODY_GRAPH.items():
            listed = {conn["region"] for conn in node["connects_to"]}
            self.assertNotIn(region_a, listed)


if __name__ == "__main__":
    unittest.main()
