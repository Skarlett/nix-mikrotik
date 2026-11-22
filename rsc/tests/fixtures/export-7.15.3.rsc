# 2026-11-22 19:24:50 by RouterOS 7.15.3
# software id = 
#
/disk
set slot1 media-interface=none media-sharing=no slot=slot1
/interface bridge
add comment=chr-deploy-check name=lan
/interface ethernet
set [ find default-name=ether1 ] disable-running-check=no mtu=9000
set [ find default-name=ether2 ] disable-running-check=no
/interface wireguard
add listen-port=51820 mtu=1420 name=wg.check
/interface list
add name=LAN
add name=WAN
/ip pool
add name=lan-pool ranges=192.168.88.10-192.168.88.254
/port
set 0 name=serial0
/interface list member
add interface=lan list=LAN
add interface=ether1 list=WAN
/ip address
add address=10.0.2.15/24 interface=ether2 network=10.0.2.0
add address=192.168.99.2/24 interface=ether1 network=192.168.99.0
add address=192.168.88.1/24 interface=lan network=192.168.88.0
/ip dhcp-client
add interface=ether1
/ip dhcp-server
add address-pool=lan-pool interface=lan name=lan-dhcp
/ip dhcp-server network
add address=192.168.88.0/24 gateway=192.168.88.1 netmask=24
/ip dns static
add address=192.168.88.1 comment="chr\"deploy\\test\$value" name=\
    chr-deploy.lan
/ip firewall address-list
add address=192.168.88.0/24 list=allowed_to_router
/ip firewall filter
add action=accept chain=input protocol=icmp
add action=accept chain=input src-address-list=allowed_to_router
/ip firewall nat
add action=masquerade chain=srcnat comment="masquerade (cost \$5/GB)" \
    out-interface-list=WAN
/system clock
set time-zone-name=UTC
/system identity
set name=chr-deploy
/system note
set show-at-login=no
/system script
add dont-require-permissions=no name=idem-probe owner=admin policy=\
    ftp,reboot,read,write,policy,test,password,sniff,sensitive,romon source=\
    ":log info \"idem-probe-ran\""
