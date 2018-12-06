#!/bin/sh

if [ $# -ne "1" ];then
   echo "The Scrpt Requires 1 Parameter....  ./getContPlacement.sh <env>"
   exit 8
fi

env=$1
cphome="/wfnse/healthchks/contPlacement/"
inventory="/wfnse/healthchks/inventory/contPlacement/"
cdllog="/wfnse/healthchks/contPlacement/cdl/"
iatlog="/wfnse/healthchks/contPlacement/iat"
uatlog="/wfnse/healthchks/contPlacement/uat"
prodlog="/wfnse/healthchks/contPlacement/prod"
mgmtlog="/wfnse/healthchks/contPlacement/mgmt"
tmpltpth="/wfnse/healthchks/contPlacement/custom-templates"
htmlpth="/wfnse/healthchks/contPlacement/html"
EMAIL=""
EMAILTEST=""
echo $EMAILTEST

if [ $env == "cdl" ];then
   mkdir -p $cdllog
   rm $cdllog/*
   ansible -m setup -i $inventory/cdlhosts all --tree $cdllog/ -bc paramiko -vvv
   cd $tmpltpth && ansible-cmdb -p host_details=0 -i $inventory/cdlhosts $cdllog  > $htmlpth/cdl-contPlacement.html
   mutt -s "CDL CONTAINER PLACEMENT REPORT" -i $htmlpth/iat-contPlacement.html -a $htmlpth/iat-contPlacement.html -- $EMAILTEST < /dev/null
elif [ $env == "iat" ];then
   mkdir -p $iatlog
   rm $iatlog/*
   ansible -m setup -i $inventory/iathosts all --tree $iatlog/ -bc paramiko -vvv
   cd $tmpltpth && ansible-cmdb -p host_details=0 -i $inventory/iathosts $iatlog/  > $htmlpth/iat-contPlacement.html
   mutt -s "IAT CONTAINER PLACEMENT REPORT" -i $htmlpth/iat-contPlacement.html -a $htmlpth/iat-contPlacement.html -- $EMAILTEST < /dev/null
elif [ $env == "prod" ];then
   mkdir -p $prodlog
   rm $prodlog/*
   cd $cphome
   /usr/bin/ansible -m setup -i $inventory/prodhosts all --tree $prodlog/ -bc paramiko -vvv
   cd $tmpltpth && /usr/bin/ansible-cmdb -p host_details=0 -i $inventory/prodhosts $prodlog/  > $htmlpth/prod-contPlacement.html
   mutt -s "PROD CONTAINER PLACEMENT REPORT" -i $htmlpth/prod-contPlacement.html -a $htmlpth/prod-contPlacement.html -- $EMAIL < /dev/null
elif [ $env == "mgmt" ];then
   mkdir -p $mgmtlog
   rm $mgmtlog/*
   ansible -m setup -i $inventory/mgmthosts all --tree $mgmtlog/ -bc paramiko -vvv
   cd $tmpltpth && ansible-cmdb -p host_details=0 -i $inventory/mgmthosts $mgmtlog/  > $htmlpth/mgmt-contPlacement.html
   mutt -s "MGMT SERVERS CONTAINER PLACEMENT REPORT" -i $htmlpth/mgmt-contPlacement.html -a $htmlpth/mgmt-contPlacement.html -- $EMAILTEST < /dev/null
elif [ $env == "dcx" ];then
   mkdir -p $prodlog $iatlog $uatlog
   rm $prodlog/* ; rm $iatlog/* ; rm $uatlog/*
   cd $cphome ; /usr/bin/ansible -m setup -i $inventory/prodhosts all --tree $prodlog/ -bc paramiko -vvv
   cd $cphome ; /usr/bin/ansible -m setup -i $inventory/iathosts all --tree $iatlog/ -bc paramiko -vvv
   cd $cphome ; /usr/bin/ansible -m setup -i $inventory/uathosts all --tree $uatlog/ -bc paramiko -vvv
   cd $tmpltpth && /usr/bin/ansible-cmdb -p host_details=0 -i $inventory/prodhosts $prodlog/  > $htmlpth/prod-contPlacement.html
   cd $tmpltpth && /usr/bin/ansible-cmdb -p host_details=0 -i $inventory/uathosts $uatlog/  > $htmlpth/uat-contPlacement.html
   cd $tmpltpth && /usr/bin/ansible-cmdb -p host_details=0 -i $inventory/iathosts $iatlog/  > $htmlpth/iat-contPlacement.html
   mutt -s "PROD CONTAINER PLACEMENT REPORT" -i $htmlpth/prod-contPlacement.html -a $htmlpth/prod-contPlacement.html -- $EMAILTEST < /dev/null
   mutt -s "UAT CONTAINER PLACEMENT REPORT" -i $htmlpth/uat-contPlacement.html -a $htmlpth/uat-contPlacement.html -- $EMAILTEST < /dev/null
   mutt -s "IAT CONTAINER PLACEMENT REPORT" -i $htmlpth/iat-contPlacement.html -a $htmlpth/iat-contPlacement.html -- $EMAILTEST < /dev/null
else
   echo "Provide the coreect Env value"
fi
exit
