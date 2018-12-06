#!/bin/bash


# Modified 04/26 to support bundle package
# Modified 8/28/2017 to remove Wily from build. Wily will be provided by Robert Conatser as separate process 

#Varables 
envidx=0
inptfile=$1
root_dir=$2

# Validation section
if [ $# -lt 1 ]; then
   echo "Usage: blueprint_gen.sh <inputfile> "
   exit 4
fi

if [ ! -f ${inptfile} ]; then
   echo "Input file is not available "
   exit 8
fi

username=`whoami`
if [ "$username" != "root" ]; then
   echo "This script need to be run as root - $username does not have adequate authority" 
   exit 8
fi

function statsmessage()
{
message=$1
status=$2

messageLen=${#message}
printf '%s' "$message"
let dashLen=80-messageLen
eval printf '%.0s-' {1..$dashLen}
printf '%s\n' ${status}

}

#Utility
# numeric_cmp()
# Input: lhs(integer) rhs(integer)
# Returns: 0 if lhs == rhs; 2 if lhs < rhs; 3 if lhs > rhs; 1 if error
# Use:     Default comparison function. See the "Use" for compare().
numeric_cmp() {
	(( $1 -eq $2 )) && return 0
	(( $1 -lt $2 )) && return 2
	(( $1 -gt $2 )) && return 3
}

##
# lexical_cmp()
# Input:   lhs(string) rhs(string)
# Returns: 0 if lhs == rhs; 2 if lhs < rhs; 3 if lhs > rhs; 1 if error
# Use:     Example lexical (alphabetical) comparison function.
#          See the "Use" for compare().
lexical_cmp() {
	[[ $1 == $2 ]] && return 0
	[[ $1 <  $2 ]] && return 2
	[[ $1  > $2 ]] && return 3
}


# compare():
# Input:   lhs rhs
# Returns: 0 if lhs == rhs; 2 if lhs < rhs; 3 if lhs > rhs; 1 if error
# Use:     Define this function in order to tell the below functions how to
#          compare values. If you don't define it, numeric_cmp will be
#          assumed.
if ! declare -f compare > /dev/null; then
	compare() {
		lexical_cmp "$@"
	}
fi

##
# qsort():  (Quick sort)
# Average:
# Stability:
# Uses:
qsort() {
	SORTEDARRAY=("$@")
	qsort_recurse 0 $((${#@}-1))	
}
qsort_recurse() {
	local -i l r m i j k # left, right, mid bounds and some iterators
	local part temp      # partition value and temporary storage
	(( l=i=$1, r=j=$2, m=(l+r)/2 ))
	part="${SORTEDARRAY[m]}"
	while ((j > i)); do
		while [[ 1 ]]; do
			compare "${SORTEDARRAY[i]}" "$part"
			(( $? == 2 && i++ )) || break
		done
		while [[ 1 ]]; do
			compare "${SORTEDARRAY[j]}" "$part"
			(( $? == 3 && j-- )) || break
		done
		if (( i <= j )); then
			temp="${SORTEDARRAY[i]}"
			SORTEDARRAY[i]="${SORTEDARRAY[j]}"
			SORTEDARRAY[j]="$temp"
			(( i++, j-- ))
		fi
	done
	(( l<j )) && qsort_recurse $l $j
	(( r>i )) && qsort_recurse $i $r
}

##
#getngarray(): Simulate two dimensional array
getngarray()
{ 
b="${nodegroup[$1]}";
eval "c=$b";
echo "${c[$2]}";
return 0;
};

##
#Recurssively change path permission
chmodpath(){
chmod $1 $2
mod=$1
if [ -d $2 ]; then
   newdir=${2%/*}
   if [ ${#newdir} -gt 1 ]; then
      chmodpath $mod $newdir
   fi
fi
}

##
#Recurssively change path permission
chownpath(){
chown $1 $2
mod=$1
if [ -d $2 ]; then
   newdir=${2%/*}
   if [ ${#newdir} -gt 1 ]; then
      chownpath $mod $newdir
   fi
fi
}

#Read from cntl file
while read line
do
   cntlarray=( ` echo $line | sed -e "s/=/ /" ` )
   serverlist[i]=${cntlarray[0]}
   i=$(( $i + 1 ))
   
   recordtype=( `echo ${cntlarray[0]} | tr "." " " `)

   case ${recordtype[0]} in
   environment) 
        envname[$envidx]=${recordtype[1]//\"/}
        envvalue[$envidx]=${cntlarray[1]//\"/}
        (( envidx += 1 )) 
	;;
   instance)
        index=${recordtype[1]}
        case ${recordtype[2]} in
          name)     name[$index]=${cntlarray[1]//\"/};;
          location) location[$index]=${cntlarray[1]//\"/};;
          portbase) portbase[$index]=${cntlarray[1]//\"/};;
          javaopts) javaopts[$index]=${cntlarray[@]:1};; 
          *)        echo "unknwon instance variable ${recordtype[2]} - process abort"
                    exit 8
                    ;;     
        esac    
	;;
   \#*)
     	#echo "comment type"
        #echo ${recordtype[0]}
	;;
   *)
     	#echo "unknown type"
        #echo ${recordtype[0]}
        ;;
   esac

done < $inptfile


#Parsing blueprint

envctr=${#envname[@]}
for (( i=0 ; i < ${envctr} ; i++ ))
do
   eval export ${envname[$i]}=${envvalue[$i]}
done

# Echo the contral parameter

echo " "
echo "Installation source files"
echo "  ANT:    $ANT_SOFTWARE"
echo "  TOMCAT: $TOMCAT_SOFTWARE"
#echo "  WILY:   $WILY_SOFTWARE"
echo "  JAVA:   $JAVA_SOFTWARE"
echo "================================"
echo "Process Kickoff at "`date`
echo " "

# Set UMASK to 022
umask 022

# Establish software binanry
if [ ! -f $ANT_SOFTWARE ]; then 
   statsmessage "Check environment variable" "fail"
   echo "==>ANT binary $ANT_SOFTWARE does not exist; Process abort" 
   exit 4
fi

if [ ! -f $TOMCAT_SOFTWARE ]; then 
   statsmessage "Check environment variable" "fail"
   echo "==>TOMCAT binary$TOMCAT_SOFTWARE does not exist; Process abort" 
   exit 4
fi

#if [ ! -f $WILY_SOFTWARE ]; then 
#   statsmessage "Check environment variable" "fail"
#   echo "==>WILY binary $WILY_SOFTWARE does not exist; Process abort" 
#   exit 4
#fi

statsmessage "Check environment variable" "ok"

#####Below users are set using gems.users role#########
#Setup operation user id
#if [ `cat /etc/passwd | grep -c wasadmin` ]; then
#   cp /home/ansible/tomcattopology/util/setup.sh /tmp/
#   /tmp/setupansible.sh
#   statsmessage "Add runtime wasadmin id " "ok"
#else
#   statsmessage "Check runtime wasadmin id " "pass"
#fi

#if [ `cat /etc/passwd | grep -c cmdbadm` ]; then
#   cp /home/ansible/tomcattopology/util/*cmdb* /tmp/
#   /tmp/setupcmdb.sh
#   statsmessage "Add runtime cmdbadm id " "ok"
#else
#   statsmessage "Check runtime cmdbadm id " "pass"
#fi
#########################################################


#Install JDK
JAVA_PROVIDER=`echo $JAVA_PROVIDER | tr ":lower:" ":upper:" `

if [ -z $JAVA_PROVIDER ]; then
   JAVA_PROVIDER="IBM"
fi

JDKRefresh="true"
if [ ! -z $JAVA_PROVIDER ] && [ $JAVA_PROVIDER == "SUN" ]; then
   #SUN JDK
   JAVA_HOME=/app/bin/sun
   if [ -d $JAVA_HOME ]; then
      if [ -L $root_dir/java ]; then 
         #Check JDK version
         $root_dir/java/bin/java -version > /tmp/javaversion.txt 2>&1
         currversion=`cat /tmp/javaversion.txt | grep -o "[0-9]\.[0-9]\.[0-9]_[0-9][0-9]-.*[0-9]" `
         echo "Java current version: ${currversion}"
         echo "Java target version:  ${JAVA_VERSION}"
         if [[ "${currversion}" < "${JAVA_VERSION}" ]]; then
            JDKRefresh="true"
         else
            JDKRefresh="false"
            statsmessage "JDK already on ${JAVA_VERSION} level, skip the JDK installation step" "ok"
         fi
      fi
   else
      mkdir -p /app/bin/sun
   fi

   if [ ${JDKRefresh} = "true" ]; then
      if [ ! -f $JAVA_SOFTWARE ]; then
         statsmessage "JDK install at $JAVA_SOFTWARE" "fail"
         echo "==>JDK binary does not exist; Process abort"
         exit 4
      fi

      actualpath=`tar -tzf ${JAVA_SOFTWARE} | head -1`
      actualpath=${actualpath%?}

      if [ `echo ${actualpath} | grep -c "jdk" ` -eq 0 ]; then
         echo "${actualpath} contains incorrect format, process abort"
         exit 8
      fi

      ACTUAL_JAVA_HOME=/app/bin/sun/${actualpath}

      # sun jdk 7 with tar.gz as suffix
      tar -xzf $JAVA_SOFTWARE -C /app/bin/sun
        
      if [ $? -ne 0 ]; then
         statsmessage "JDK install use $JAVA_SOFTWARE" "fail"
         echo "==>failed to untar $JAVA_SOFTWARE, process abort"
         exit 8
      fi
   fi

else
   #IBM JDK
   JAVA_HOME=/app/bin/ibm
   if [ ! -d $JAVA_HOME ]; then
      if [ -L $root_dir/java ]; then 
         #Check JDK version
         $root_dir/java/bin/java -version > /tmp/javaversion.txt 2>&1
         platform=`uname -p`
         if [ ${platform} = "s390x" ]; then
            currversion=`cat /tmp/ibmjdkVersion.txt | grep -o "pxz.*" `
         else
            currversion=`cat /tmp/ibmjdkVersion.txt | grep -o "pxa.*" `
         fi
         currversion=${currversion%%(*}
         echo "Java current version: ${currversion}"
         echo "Java target version:  ${JAVA_VERSION}"
         if [[ "${currversion}" < "${JAVA_VERSION}" ]]; then
            JDKRefresh="true"
         else
            JDKRefresh="false"
            statsmessage "JDK already on ${JAVA_VERSION} level, skip the JDK installation step" "ok"
         fi
      fi 
   else
      mkdir -p /app/bin/ibm
   fi   


   if [ ${JDKRefresh} = "true" ]; then
      if [ ! -f $JAVA_SOFTWARE ]; then
         statsmessage "JDK install at $JAVA_SOFTWARE" "fail"
         echo "==>JDK binary does not exist; Process abort"
         exit 4
      fi

      installsuffix=${JAVA_SOFTWARE##*.}
      if [ ${installsuffix} == "tgz" ]; then
         #The java path may already included in tgz file
         actualpath=`tar -tzf ${JAVA_SOFTWARE} | head -1`
         actualpath=${actualpath%?}
         platform=`uname -p`

         if [ ${platform} = "s390x" ]; then
            jdkstring="s390"
         else
            jdkstring="java-x86"
         fi

         if [ `echo ${actualpath} | grep -c ${jdkstring} ` -eq 0 ]; then
            echo "${actualpath} contains incorrect format, process abort"
            exit 8
         fi

         ACTUAL_JAVA_HOME=/app/bin/ibm/${actualpath}

      fi

      mkdir -p $JAVA_HOME
      if [ ${installsuffix} == "tgz" ]; then
         tar -xzf $JAVA_SOFTWARE -C /app/bin/ibm
      else
         tar -xf $JAVA_SOFTWARE -C $JAVA_HOME
      fi

      if [ $? -ne 0 ]; then
         statsmessage "JDK install use $JAVA_SOFTWARE" "fail"
         echo "==>failed to untar $JAVA_SOFTWARE, process abort"
         exit 8
      fi
   fi
fi 

#Install JDK Common Section
if [ ${JDKRefresh} = "true" ]; then
   if [ -L $root_dir/java ]; then 
      rm $root_dir/java
   fi
   if [ -L /app/bin/java ]; then 
      rm /app/bin/java
   fi

   ln -s ${ACTUAL_JAVA_HOME} $root_dir/java
   ln -s ${ACTUAL_JAVA_HOME} /app/bin/java

   chown -R wasadmin:mqm ${ACTUAL_JAVA_HOME}
   chmodpath o+rx ${JAVA_HOME}
   statsmessage "JDK install to $ACTUAL_JAVA_HOME" "ok"
fi

#Install tomcat software 
TomcatRefresh="true"

TOMCAT_HOME=/app/bin/apache
if [ -L $root_dir/tomcat ]; then
   #Check tomcat version
   $root_dir/java/bin/java -cp $root_dir/tomcat/lib/catalina.jar org.apache.catalina.util.ServerInfo > /tmp/tomcatversion.txt 2>&1
   data=( `cat /tmp/tomcatversion.txt | grep "Server number:" ` )
   currversion=${data[2]}

   echo "Tomcat current version: ${currversion}"
   echo "Tomcat target version:  ${TOMCAT_VERSION}"
   if [[ "${currversion}" < "${TOMCAT_VERSION}" ]]; then 
      TomcatRefresh="true"
   else
      TomcatRefresh="false"
      statsmessage "Tomcat already on ${TOMCAT_VERSION} level, skip the Tomcat installation step" "ok"
   fi
fi
if [ ${TomcatRefresh} = "true" ]; then
   mkdir -p ${TOMCAT_HOME}
   tar -xzf ${TOMCAT_SOFTWARE} -C ${TOMCAT_HOME}
   if [ $? -ne 0 ]; then
      statsmessage "TOMCAT installed at $TOMCAT_HOME" "fail"
      exit 8
   fi

   tomcat_ver=`tar -tvzf $TOMCAT_SOFTWARE | head -1| awk '{ print $6 }' `
   CATALINA_HOME=${TOMCAT_HOME}/${tomcat_ver%%/*}
   if [ -L $root_dir/tomcat ]; then
      rm $root_dir/tomcat
   fi
   if [ -L /app/bin/tomcat ]; then
      rm /app/bin/tomcat
   fi

   ln -s $CATALINA_HOME $root_dir/tomcat
   ln -s $CATALINA_HOME /app/bin/tomcat

   chown -R wasadmin:mqm ${TOMCAT_HOME}
   chmodpath o+rx ${TOMCAT_HOME}
else
   tomcat_ver=`tar -tvzf $TOMCAT_SOFTWARE | head -1| awk '{ print $6 }' `
   CATALINA_HOME=${TOMCAT_HOME}/${tomcat_ver%%/*}
fi

#Install Tomcat APR if needed
if [ ! -z ${TOMCAT_APR} ] && [ ${TOMCAT_APR} == "true" ]; then
   aprctr=`rpm -qa | grep -c libapr1-devel`
   if [ ${aprctr} -lt 1 ]; then
      zypper -n in libapr1-devel
   fi
   opensslctr=`rpm -qa | grep -c libopenssl-devel`
   if [ ${opensslctr} -lt 1 ]; then
      zypper -n in libopenssl-devel
   fi
   cp ${CATALINA_HOME}/bin/tomcat-native.tar.gz /tmp
   cd /tmp
   tar xvf tomcat-native.tar.gz
   cd /tmp/tomcat-native-*/jni/native
   ./configure --with-apr=/usr/bin/apr-1-config --with-ssl=yes --with-java-home=$root_dir/java --prefix=${CATALINA_HOME}
   if [ $? -ne 0 ]; then
      statsmessage "Tomcat APR installation" "fail"
      exit 8
   fi 
   make
   make install
   statsmessage "Tomcat APR installation" "ok"

fi  


#Install ANT
ANT_HOME=/app/bin/apache
ANTcatRefresh="true"

TOMCAT_HOME=/app/bin/apache
if [ -L $root_dir/ant ]; then
   #Check ant version
   export JAVA_HOME=$root_dir/java
   $root_dir/ant/bin/ant -version > /tmp/antversion.txt
   currversion=`cat /tmp/antversion.txt | grep -o "[0-9]\.[0-9]\.[0-9]" `

   echo "ANT current version: ${currversion}"
   echo "ANT target version:  ${ANT_VERSION}"
   if [[ "${currversion}" < "${ANT_VERSION}" ]]; then
      ANTcatRefresh="true"
   else
      ANTcatRefresh="false"
      statsmessage "ANT already on ${ANT_VERSION} level, skip the ANT installation step" "ok"
   fi
fi

if [ ${ANTcatRefresh} = "true" ]; then
   mkdir -p $ANT_HOME
   unzip -q $ANT_SOFTWARE -d $ANT_HOME
   if [ $? -ne 0 ]; then
      statsmessage "ANT installed at $ANT_SOFTWARE" "fail"
      echo "==>failed to unzip $ANT_SOFTWARE, process abort"
      exit 8
   fi
   ant_version=`unzip -l $ANT_SOFTWARE | head -5 | tail -1 | awk '{print $4 }' `
   if [ -L $root_dir/ant ]; then
      rm $root_dir/ant
   fi
   if [ -L /app/bin/ant ]; then
      rm /app/bin/ant
   fi

   ln -s $ANT_HOME/${ant_version%%/*} $root_dir/ant
   ln -s $ANT_HOME/${ant_version%%/*} /app/bin/ant
 
   chown -R wasadmin:mqm ${ANT_HOME}
   chmodpath o+rx ${ANT_HOME}
   statsmessage "ANT installed at $ANT_HOME/${ant_version%%/*}" "ok"
fi

#20170828 Remove Install Wily

#Populate tomcat specific jar to ANT thru symbolic link
cp $root_dir/tomcat/lib/catalina-ant.jar $root_dir/ant/lib/
cp $root_dir/tomcat/lib/tomcat-coyote.jar $root_dir/ant/lib/
cp $root_dir/tomcat/lib/tomcat-util.jar $root_dir/ant/lib/
cp $root_dir/tomcat/bin/tomcat-juli.jar $root_dir/ant/lib/
chown -R wasadmin:mqm ${ANT_HOME}
statsmessage "Copy Tomcat jar file to ANT" "ok"

# Install Oracle data source UCP
${UCPDRIVER:="false"}
if [ $UCPDRIVER == "true" ]; then
   if [ -d $UCPDRIVERLOCATION ]; then
      cp $UCPDRIVERLOCATION/ucp.jar ${CATALINA_HOME}/lib/
      cp $UCPDRIVERLOCATION/ojdbc6.jar ${CATALINA_HOME}/lib/    
      statsmessage "UCP DRiver installation" "ok"
   else
      statsmessage "UCP DRiver installation" "fail"
      echo "==> $UCPDRIVERLOCATION is not a directory"
   fi
fi 

# Install WMQ 
${WMQ:="false"}
if [ $WMQ == "true" ]; then
   if [ -d $WMQLOCATION ]; then
      cp $WMQLOCATION/*.jar ${CATALINA_HOME}/lib/
      statsmessage "WMQ installation" "ok"
   else
      statsmessage "WMQ installation" "fail"
      echo "==> $WMQLOCATION is not a directory"
   fi
fi 

#Install application deployment infrastructure
tar -xpf /home/ansible/tomcattopology/util/tomcat_deploy.tar -C /
if [ $? -ne 0 ]; then
   statsmessage "Application deployment Structure installation" "fail"
   echo "==>failed to untar application deployment, process abort"
   exit 8
fi
statsmessage "Application deployment Structure installation" "ok"

# Change ownership of tomcat binary
chown -R wasadmin:mqm $root_dir/tomcat/
if [ $? -eq 0 ]; then
   statsmessage "Change Tomcat Binary ownership to wasadmin" "ok"
else
   statsmessage "Change Tomcat Binary ownership to wasadmin" "fail"
fi

#Create Tomcat Instance 
instctr=${#name[@]}
for (( i=1 ; i <= ${instctr} ; i++ ))
do

   #Generate Instance 
   echo "==>Process instance ${name[i]} - location ${location[i]}"
   echo "   CATALINA_HOME: ${CATALINA_HOME} "
   mkdir -p ${location[$i]}
   if [ ${location[$i]} == "default" ]; then
      CATALINA_BASE=${CATALINA_HOME}
   else
      CATALINA_BASE=${location[$i]}
      cp -a $CATALINA_HOME/conf ${CATALINA_BASE}/
      cd ${CATALINA_BASE}; mkdir -p common logs temp server shared webapps work bin
      #Commentt out copy manager file
      #cp -r ${CATALINA_HOME}/webapps/*  ${CATALINA_BASE}/webapps/

      chown -R wasadmin:mqm ${CATALINA_BASE}
   fi
   echo "   CATALINA_BASE: ${CATALINA_BASE} "

   #Remove deafault doc and examples
   #rm -r ${CATALINA_BASE}/webapps/docs
   #rm -r ${CATALINA_BASE}/webapps/examples
   #2014/04/19 add next two lines as part of Tomcat harden process
   #rm -r ${CATALINA_BASE}/webapps/ROOT
   #rm -r ${CATALINA_BASE}/webapps/host-manager

   #2014/04/19 add the following lines as part of Tomcat harden process
   mkdir -p ${CATALINA_BASE}/conf/Catalina/localhost/
   if [ "${TOMCAT_Manager}" = "true" ]; then
      cp -rp ${CATALINA_HOME}/webapps/manager  ${CATALINA_BASE}/webapps/
      cp /home/ansible/tomcattopology/util/manager.xml ${CATALINA_BASE}/conf/Catalina/localhost/
   fi
   chown -R wasadmin:mqm ${CATALINA_BASE}/conf/Catalina
   #sed -i '155i\      <url-pattern>/text/list</url-pattern>' ${CATALINA_BASE}/webapps/manager/WEB-INF/web.xml

   #Generate verboseGC location
   mkdir -p $root_dir/test/logs/${name[i]}
   chmodpath 755 $root_dir/test/logs/${name[i]}
   chown "wasadmin:mqm" $root_dir/test/logs/${name[i]}

   if [ ${location[$i]} == "default" ]; then
   cp ${CATALINA_HOME}/bin/startup.sh ${CATALINA_HOME}/bin/startup.sh.orig
   sed "/EXECUTABLE=catalina.sh/a \\
# test change start here \\
export JAVA_HOME=$root_dir/java \\
export JAVA_OPTS=\"\${JAVA_OPTS} \" \\
# test change end here " ${CATALINA_HOME}/bin/startup.sh.orig > ${CATALINA_HOME}/bin/startup.sh
   cp ${CATALINA_HOME}/bin/shutdown.sh ${CATALINA_HOME}/bin/shutdown.sh.orig
   sed "/EXECUTABLE=catalina.sh/a \\
# test change start here \\
export JAVA_HOME=$root_dir/java \\
JAVA_OPTS=${javaopts[i]} \\
export JAVA_OPTS=\"\${JAVA_OPTS} \" \\
# test change end here " ${CATALINA_HOME}/bin/shutdown.sh.orig > ${CATALINA_HOME}/bin/shutdown.sh

   else

      cat > ${CATALINA_BASE}/bin/startup.sh <<EOF
umask 022 

export JAVA_HOME=/app/bin/java
export JRE_HOME=/app/bin/java
export CATALINA_HOME=/app/bin/tomcat
export CATALINA_BASE=${CATALINA_BASE}
export CATALINA_PID=\${CATALINA_BASE}/logs/tomcat.pid


JAVA_OPTS=${javaopts[i]}

export JAVA_OPTS="\${JAVA_OPTS} "

\${CATALINA_HOME}/bin/startup.sh

EOF
      cat > ${CATALINA_BASE}/bin/shutdown.sh <<EOF
export JAVA_HOME=/app/bin/java
export JRE_HOME=/app/bin/java
export CATALINA_HOME=/app/bin/tomcat
export CATALINA_BASE=${CATALINA_BASE}
export CATALINA_PID=\${CATALINA_BASE}/logs/tomcat.pid

\${CATALINA_HOME}/bin/shutdown.sh 30 force

EOF
   fi

   chmod 755 ${CATALINA_BASE}/bin/*.sh

   #Allow us to use ant to deploy the code
   cp /home/ansible/tomcattopology/util/tomcat-users.xml ${CATALINA_BASE}/conf/

   #Change server port configuration
   #Default port: 		server 8005 HTTP 8080 HTTPS 8443 AJP 8009
   # To avoid port conflict 	server 8005 HTTP 8080 HTTPS 8443 AJP 18009 + base
   base=${portbase[i]}
   let httpport=8080+$base
   let httpsport=8443+$base
   let serverport=8005+$base
   let ajpport=8009+$base

   if [ ${location[$i]} == "default" ]; then
      cp $CATALINA_HOME/conf/server.xml $CATALINA_HOME/conf/server.xml.orig
      sed -e "s/port=\"8080\"/port=\"${httpport}\"/g" -e "s/redirectPort=\"8443\"/redirectPort=\"${httpsport}\"/g" -e "s/port=\"8005\"/port=\"${serverport}\"/g" -e "s/port=\"8009\"/port=\"${ajpport}\"/g" $CATALINA_HOME/conf/server.xml.orig > $CATALINA_HOME/conf/server.xml
      #2014/04/19 add the following lines as part of Tomcat harden process
      sed -i "s/resourceName=\"UserDatabase\"\/>/resourceName=\"UserDatabase\" digest=\"sha-256\" \/>/" ${CATALINA_HOME}/conf/server.xml

   else
      sed -e "s/port=\"8080\"/port=\"${httpport}\"/g" -e "s/redirectPort=\"8443\"/redirectPort=\"${httpsport}\"/g" -e "s/port=\"8005\"/port=\"${serverport}\"/g" -e "s/port=\"8009\"/port=\"${ajpport}\"/g" $CATALINA_HOME/conf/server.xml > $CATALINA_BASE/conf/server.xml
      #2014/04/19 add the following lines as part of Tomcat harden process
      sed -i "s/resourceName=\"UserDatabase\"\/>/resourceName=\"UserDatabase\" digest=\"sha-256\" \/>/" ${CATALINA_BASE}/conf/server.xml

   fi

   #Place mark for test artifact
   suffix=`date +"%Y%m%d_%H%M"`
   cp $CATALINA_BASE/conf/server.xml $CATALINA_BASE/conf/server.xml.${suffix}
   sed '/<\/Host>/i \
        <!-- test artifact start here --> ' $CATALINA_BASE/conf/server.xml.${suffix} > $CATALINA_BASE/conf/server.xml
   #Create port propertie
   cat > ${CATALINA_BASE}/conf/instance.properties <<EOF
httpport=${httpport}
httpsport=${httpsport}
serverport=${serverport}
ajpport=${ajpport}

EOF

   statsmessage "Tomcat Instance $i setup" "ok"

done

if [ ! -L /home/tomcatprofile ]; then

   if [ ${location[1]} == "default" ]; then
      mkdir -p /home/tomcatprofile
      chown wasadmin:mqm /home/tomcatprofile
      chown -R wasadmin:mqm ${CATALINA_HOME} 
      ln -s ${CATALINA_HOME} /home/tomcatprofile/default
   else
      ln -s /app/tomcatprofile /home/tomcatprofile
      chown -R wasadmin:mqm /app/tomcatprofile
   fi 
fi

#Start newly created instance
instctr=${#name[@]}
for (( i=1 ; i <= ${instctr} ; i++ ))
do
   if [ ${location[$i]} == "default" ]; then
      CATALINA_BASE=${CATALINA_HOME}
   else
      CATALINA_BASE=${location[$i]}
   fi
   echo "==>starting Tomcat insatnce ${name[i]}"
   
   chown -R wasadmin:mqm ${CATALINA_BASE}

   su - wasadmin -c "${CATALINA_BASE}/bin/startup.sh"
   base=${portbase[i]}
   let httpport=8080+$base
   sleep 15
   statuscount=`netstat -an | grep -c ${httpport}`
   echo "==> Waiting for 15 seconds and checking port $httpport status"
   if [ $statuscount -eq 0 ]; then
      statsmessage "Tomcat Instance ${name[i]} startup" "fail"
   else
      statsmessage "Tomcat Instance ${name[i]} startup" "ok"
   fi
   
   #Check manager application status after restart
   #cd /tmp; rm -f list
   #wget http://localhost:${httpport}/manager/text/list --http-user=appscript --http-password=T0m5phere 1>/dev/null 2>&1
   #listctr=`cat list | grep -c "manager:running" `
   #if [ $listctr -eq 0 ]; then
   #   statsmessage "manager application start on Tomcat Instance ${name[i]} " "fail"
   #else
   #   statsmessage "manager application start on Tomcat Instance ${name[i]} " "ok"
   #fi 

done

#Add tomcat instance to autostart
cp /home/ansible/tomcattopology/util/tomcatd /etc/init.d/
chkconfig tomcatd on 1>/dev/null 2>&1
if [ $? -eq 0 ]; then
   statsmessage "Setup autostart script tomcatd" "ok"
else
   statsmessage "Setup autostart script tomcatd" "fail"
fi

echo "Tomcat Build process completed at " `date`

#Commenting below because the path $root_dir is hard-coded, so it will fail for sles12 paths
#Below is jsut for info purpose anyway
#/home/ansible/tomcattopology/sh//tomcat_bundleVersionInfo.sh 

exit

