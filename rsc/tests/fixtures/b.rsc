# The same router after a change: a VLAN and its address are added, a pool
# range is widened its comment dropped, a DNS entry is gone, the input chain
# gains a rule and is reordered, and the masquerade comment is corrected.
/system identity
set name="chr-b"
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
/interface vlan
add interface=bridge name=vlan20 vlan-id=20
/interface wireguard
add listen-port=51820 mtu=1420 name=wg0 private-key=__MIKROTIK_SECRET_wg-key/privkey__
/interface wireguard peers
add allowed-address=10.44.0.0/24 interface=wg0 name=peer-a public-key="k9ZRM5a4m4qYDVuZmbksipA/gJ82mBH3MvgZaJRWIAo="
/ip address
add address=10.10.10.1/24 interface=bridge network=10.10.10.0
add address=10.10.12.1/24 interface=ether3 network=10.10.12.0
add address=10.10.20.1/24 interface=vlan20 network=10.10.20.0
/ip pool
add name=lan-pool ranges=10.10.10.100-10.10.10.250
/ip dhcp-server
add address-pool=lan-pool disabled=no interface=bridge name=dhcp-lan
/ip dhcp-server network
add address=10.10.10.0/24 gateway=10.10.10.1 netmask=24
add address=10.10.12.0/24 gateway=10.10.12.1 netmask=24
/ip dns
set allow-remote-requests=yes servers=9.9.9.9
/ip firewall filter
add action=accept chain=input comment="defconf: accept icmp" protocol=icmp
add action=accept chain=input comment="defconf: accept established,related" connection-state=established,related
add action=accept chain=input comment="defconf: accept dhcp" dst-port=67 protocol=udp
add action=drop chain=input comment="defconf: drop all not coming from LAN" in-interface-list=!LAN
/ip firewall nat
add action=masquerade chain=srcnat comment="defconf: masquerade WAN" out-interface-list=WAN
/ip service
set telnet disabled=yes
set ftp disabled=yes
/system clock
set time-zone-name=Europe/Stockholm