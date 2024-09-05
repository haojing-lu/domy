#fix luci-app-transmission
sed -i 's/transmission-daemon-openssl/transmission-daemon/' feeds/luci/applications/luci-app-transmission/Makefile

#update transmission transmission-web-control
git clone --single-branch https://github.com/openwrt/packages mytmp/packages
rm -rf feeds/packages/net/transmission
rm -rf feeds/packages/net/transmission-web-control
cp -a mytmp/packages/net/transmission feeds/packages/net/
cp -a mytmp/packages/net/transmission-web-control feeds/packages/net/
[ -d feeds/packages/libs/libb64 ] || cp -a mytmp/packages/libs/libb64 package/libs/
[ -d feeds/packages/libs/libdeflate ] || cp -a mytmp/packages/libs/libdeflate package/libs/
[ -d feeds/packages/libs/libdht ] || cp -a mytmp/packages/libs/libdht package/libs/
[ -d feeds/packages/libs/libutp ] || cp -a mytmp/packages/libs/libutp package/libs/
rm -rf mytmp
