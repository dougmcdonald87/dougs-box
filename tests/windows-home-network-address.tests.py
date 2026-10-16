import importlib.util,pathlib,unittest
P=pathlib.Path(__file__).resolve().parents[1]/'scripts/windows_home_network_address.py'
spec=importlib.util.spec_from_file_location('network_address',P)
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class ProbeAddressTests(unittest.TestCase):
 def test_private_subnet_uses_unused_address_and_preserves_gateway(self):
  self.assertEqual(m.pick_probe_address('172.20.0.0/16','172.20.0.1',[]),{'address':'172.20.255.253','prefix':16,'gateway':'172.20.0.1'})
 def test_known_collision_refuses_instead_of_reusing_address(self):
  with self.assertRaises(ValueError):m.pick_probe_address('192.168.7.0/24','192.168.7.1',['192.168.7.253'])
 def test_public_noncanonical_wrong_gateway_and_small_network_refused(self):
  for prefix,gateway in [('8.8.8.0/24','8.8.8.1'),('172.20.1.0/16','172.20.0.1'),('10.0.0.0/24','10.1.0.1'),('10.0.0.0/30','10.0.0.1'),('10.0.0.0/8','10.0.0.1'),('fc00::/64','fc00::1')]:
   with self.subTest(prefix=prefix),self.assertRaises(ValueError):m.pick_probe_address(prefix,gateway,[])
 def test_gateway_cannot_be_network_broadcast_or_probe_address(self):
  for gateway in ['10.0.0.0','10.0.0.255','10.0.0.253']:
   with self.subTest(gateway=gateway),self.assertRaises(ValueError):m.pick_probe_address('10.0.0.0/24',gateway,[])
if __name__=='__main__':unittest.main()
