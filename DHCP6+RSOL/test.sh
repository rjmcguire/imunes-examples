#!/bin/sh

. ../common/procedures.sh

pcs="FIX PC1 PC2"
err=0

eid=`imunes -b DHCP6.imn | awk '/Experiment/{print $4; exit}'`
startCheck "$eid"

./start_dhcpd6 $eid
if [ $? -ne 0 ]; then
    echo "********** START_DHCP6 ERROR **********"
    pcs=""
    err=1
fi

if [ $err -eq 0 ]; then
    sleep 5
    for pc in $pcs; do
	ip_addr=`getNodeIP6 $pc@$eid eth0`
	echo $ip_addr | grep -q "fc00:3::"
	if [ $? -ne 0 ]; then
	    echo "********** IFCONFIG ERROR **********"
	    err=1
	    break
	fi

	n=1
	pingStatus=1
	while [ $n -le 20 ] && [ $pingStatus -ne 0 ]; do
	    echo "Ping6 test $n / 20 ..."
	    ping6Check $pc@$eid fc00:3::1
	    pingStatus=$?
	    n=`expr $n + 1`
	    sleep 1
	done

	if [ $pingStatus -ne 0 ]; then
	    err=$pingStatus
	    break
	fi
    done
fi

if [ $err -eq 0 ]; then
    netDump PC3@$eid eth0 'port 546 and not arp or port 547 and not arp'
    if [ $? -eq 0 ]; then
        sleep 2
	if isOSfreebsd; then
	    pre="/usr/local/sbin/"
	fi
	himage PC3@${eid} ${pre}dhclient -6 eth0
        if [ $? -eq 0 ]; then
            sleep 2
            readDump PC3@$eid eth0
            err=$?
        else
            echo "********** DHCLIENT ERROR **********"
            err=1
        fi
    else
        err=1
    fi
fi

./start_stateless $eid
if [ $? -ne 0 ]; then
    echo "********** START_STATELESS ERROR **********"
    pcs=""
    err=1
fi

for pc in $pcs; do
    n=1
    pingStatus=1
    while [ $n -le 20 ] && [ $pingStatus -ne 0 ]; do
        echo "Ping6 test $n / 20 ..."
	ping6Check $pc@$eid fc00:2::10
        pingStatus=$?
        n=`expr $n + 1`
	sleep 1
    done

    if [ $pingStatus -ne 0 ]; then
	err=$pingStatus
        break
    fi
done

imunes -b -e $eid

thereWereErrors $err
