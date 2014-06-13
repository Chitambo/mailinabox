# DNS: Configure a DNS server using nsd
#######################################

# This script installs packages, but the DNS zone files are only
# created by the /dns/update API in the management server because
# the set of zones (domains) hosted by the server depends on the
# mail users & aliases created by the user later.

source setup/functions.sh # load our functions

# Install nsd, our DNS server software, and ldnsutils which helps
# us sign zones for DNSSEC.

# ...but first, we have to create the user because the 
# current Ubuntu forgets to do so in the .deb
# see issue #25 and https://bugs.launchpad.net/ubuntu/+source/nsd/+bug/1311886
if id nsd > /dev/null 2>&1; then
	true; #echo "nsd user exists... good";
else
	useradd nsd;
fi

# Okay now install the packages.

apt_install nsd ldnsutils

# Prepare nsd's configuration.

sudo mkdir -p /var/run/nsd

# Create DNSSEC signing keys.

mkdir -p "$STORAGE_ROOT/dns/dnssec";
if [ ! -f "$STORAGE_ROOT/dns/dnssec/keys.conf" ]; then
	# These two steps take a while.

	# Create the Key-Signing Key (KSK) (-k) which is the so-called
	# Secure Entry Point. Use a NSEC3-compatible algorithm (best
	# practice), and a nice and long keylenght. The domain name
	# we provide doesn't matter and is only used in the filename.
	# Since we'll use the same keys for all our domains, use a
	# generic string "_domain_" to indicate the domain name.
	KSK=$(umask 077; cd $STORAGE_ROOT/dns/dnssec; ldns-keygen -a RSASHA1-NSEC3-SHA1 -b 2048 -k _domain_);

	# Now create a Zone-Signing Key (ZSK) which is expected to be
	# rotated more often than a KSK, although we have no plans to
	# rotate it (and doing so would be difficult to do without
	# disturbing DNS availability.) Omit '-k' and use a shorter key.
	ZSK=$(umask 077; cd $STORAGE_ROOT/dns/dnssec; ldns-keygen -a RSASHA1-NSEC3-SHA1 -b 1024 _domain_);

	# These generate two sets of files like:
	# K_domain_.+007+08882.ds <- DS record for adding to NSD configuration files
	# K_domain_.+007+08882.key <- public key (goes into DS record & upstream DNS provider like your registrar)
	# K_domain_.+007+08882.private  <- private key (secret!)

	# The filenames are unpredictable and encode the key generation
	# options. So we'll store the names of the files we just generated.
	# We might have multiple keys down the road. This will identify
	# what keys are the current keys.
	cat > $STORAGE_ROOT/dns/dnssec/keys.conf << EOF;
KSK=$KSK
ZSK=$ZSK
EOF
fi

# Force the dns_update script to be run every day to re-sign zones for DNSSEC.
echo "curl -d GO http://localhost:10222/dns/update" > /etc/cron.daily/mailinabox-dnssec
chmod +x /etc/cron.daily/mailinabox-dnssec

# Permit DNS queries on TCP/UDP in the firewall.

ufw_allow domain

