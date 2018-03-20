#!/bin/sh

###################################################################################
# Global Variables
###################################################################################
CURPATH=`pwd`
FIOPATH=$CURPATH/fio

###################################################################################
# COMPILE ENVIRONMENT CHECK
###################################################################################
envirocheck()
{
    if which fio ; then 
	echo -e "\n   fio has install    \n"
	return 1
    fi

    if rpm -qa | grep "libaio-dev"; then
            echo  -e "\n    libaio & libaio-dev has installed   \n"           
    else
            yum install -y libaio
            yum install -y libaio-devel
    fi
    return 0
}

###################################################################################
# DOWNLOAD TAG : fio-2.10 
###################################################################################

fioinstall()
{
    if [ ! -d "$CURPATH/fio"  ]; then
    	git clone https://github.com/hubzhangxj/fio.git -b fio-2.10
    else
    	echo  -e "\n    Fio has cloned, Note that version 2.10    \n"		
    fi
    pushd $FIOPATH
    ./configure
    make
    make install
    popd

    return 0
}

if ! envirocheck; then
	echo -e "\033[31mError! FIO has installed!\033[0m"
else
    if ! fioinstall; then
	    echo -e "\033[31mError! Download & Install fio failed!\033[0m" 
    fi
fi

#if ! compile; then
#	echo -e "\033[31mError! Compile fio failed!\033[0m" ; exit 1
#fi

#reference: http://www.cnblogs.com/lichkingct/archive/2010/08/27/1810463.html
#ps -ef |grep fio |grep -v grep|cut -c 9-15|xargs kill -9
