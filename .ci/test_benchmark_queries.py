import unittest
from benchmark_queries import normalize, summarize


class BenchmarkTests(unittest.TestCase):
    def test_equivalent_link_fields_and_duplicates(self):
        moon = dict(index=1, name='lo', mtu=65536, flags=0x49)
        ip = dict(ifindex=1, ifname='lo', mtu=65536, flags=['UP', 'LOOPBACK'])
        self.assertEqual(normalize([moon], 'moonnet'), normalize([ip], 'ip'))
        with self.assertRaises(ValueError):
            normalize([moon, moon], 'moonnet')

    def test_nearest_rank_p95_retains_outliers(self):
        values = list(range(1, 21))
        self.assertEqual(summarize(values)['p95_ns'], 19)
        self.assertEqual(summarize([1, 100])['p95_ns'], 100)


if __name__ == '__main__':
    unittest.main()
