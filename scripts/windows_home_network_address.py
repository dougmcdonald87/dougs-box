"""Choose a temporary probe address on an existing private runner NAT subnet.

No networking or external calls. Runtime subnet details must stay on the runner.
"""
import ipaddress

def pick_probe_address(prefix,gateway,in_use):
    network=ipaddress.ip_network(prefix,strict=True)
    if network.version!=4 or not 16<=network.prefixlen<=28:
        raise ValueError('Unsupported probe subnet')
    private=[ipaddress.ip_network(x) for x in ('10.0.0.0/8','172.16.0.0/12','192.168.0.0/16')]
    if not any(network.subnet_of(x) for x in private):raise ValueError('Private subnet required')
    router=ipaddress.ip_address(gateway)
    candidate=network.broadcast_address-2
    if router not in network or router in (network.network_address,network.broadcast_address,candidate):raise ValueError('Invalid probe gateway')
    occupied={ipaddress.ip_address(x) for x in in_use}
    if candidate in occupied:raise ValueError('Probe address occupied')
    return {'address':str(candidate),'prefix':network.prefixlen,'gateway':str(router)}

if __name__=='__main__':
    import json,sys
    try:print(json.dumps(pick_probe_address(sys.argv[1],sys.argv[2],sys.argv[3:])))
    except Exception:sys.exit('Private runner probe address refused')
