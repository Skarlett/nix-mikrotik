/system script
add dont-require-permissions=no name=luninet-sync owner=admin policy=\
    read,write,test source="\
    \n:local url \"https://example.invalid/luni-controllers.json\"\
    \n:local interface \"luninet-clients\"\
    \n:local ownkey [/interface/wireguard get \$interface public-key]\
    \n:if (\$ownkey != \"\") do={\
    \n    :log info \"wg sync: keeping \$ownkey\"\
    \n}\
    \n"
