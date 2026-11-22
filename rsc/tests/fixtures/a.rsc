# A router written the way the renderer in this repository emits one.
# Used as the "before" side of the upsert test.
/system identity
set name="chr-a"
/interface bridge
add auto-mac=no comment="defconf" name=bridge
/interface bridge port
add bridge=bridge interface=ether2
add bridge=bridge interface=ether3
/interface list
add name=LAN
add name=WAN
/interface list member
add interface=bridge list=LAN
add interface=ether1 list=WAN
/interface wireguard
add listen-port=51820 mtu=1420 name=wg0 private-key=__MIKROTIK_SECRET_wg-key/privkey__
/interface wireguard peers
add allowed-address=10.44.0.0/24 interface=wg0 name=peer-a public-key="k9ZRM5a4m4qYDVuZmbksipA/gJ82mBH3MvgZaJRWIAo="
/ip address
add address=10.10.10.1/24 interface=bridge network=10.10.10.0
add address=10.10.11.1/24 interface=ether3 network=10.10.11.0
/ip pool
add name=lan-pool ranges=10.10.10.100-10.10.10.200 comment="dhcp for LAN"
/ip dhcp-server
add address-pool=lan-pool disabled=no interface=bridge name=dhcp-lan
/ip dhcp-server network
add address=10.10.10.0/24 gateway=10.10.10.1 netmask=24
/ip dns
set allow-remote-requests=yes servers=1.1.1.1,1.0.0.1
/ip dns static
add address=10.10.10.1 name=router.lan
/ip firewall filter
add action=accept chain=input comment="defconf: accept established,related" connection-state=established,related
add action=accept chain=input comment="defconf: accept icmp" protocol=icmp
add action=drop chain=input comment="defconf: drop all not coming from LAN" in-interface-list=!LAN
/ip firewall nat
add action=masquerade chain=srcnat comment="defconf: masquerade" out-interface-list=WAN
/system clock
set time-zone-name=Europe/Stockholm