# A script, not an export: RouterOS addresses a menu with a block, and what the
# block adds depends on a loop variable. Nothing here is a configuration the
# differ could compute, so it has to be kept verbatim rather than refused.
:foreach neighbor in=$NEIGHBORS do={
    :local NAME     ($neighbor->"name")
    :local WGIFNAME ("wg." . $NAME)
    /interface {
        wireguard {
            add name=$IFNAME
            # Only add the peer if a public key has been provided.
            if ($WGPUBKEY) do={
                peers add                       \
                interface=$WGIFNAME             \
                public-key=$WGPUBKEY            \
                allowed-address=::/0,0.0.0.0/0
            }
        }
        eoipv6 {
            add                                 \
            name=$IFNAME                        \
            # TODO
        }
    }
    /ipv6 address add interface=$WGIFNAME address=$PREFIX
} ;; add 10.20.64.0/18 to clients
/ip dhcp-server option
add code=121 name=classless-route value=0x120a14400a010001
