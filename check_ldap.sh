#!/bin/bash

servidor="ip-del-servidor-ldap"

###################################################################
# FUNCIONES AUXILIARES
###################################################################

function mensaje() {

   texto=$1
   contenido=$2
   indentado=$3
   if [ -n "$contenido" ]
   then
      echo -n "$texto"
      if [ "$indentado" != "true" ]
      then
           echo "$contenido"
      else
           echo ""
           for linea in $contenido 
           do
               echo -e "\t$linea"
           done
      fi
      echo ""
   fi
}

function clean_duplicates() {
   #Esta función la ha hecho chatgpt
   #Recibe una lista de strings y se queda con aquellos que no están contenidos dentro de otro string de la propia lista.
   input=$1
   output=""
   for i in $input
   do
      contained=false
      for j in $input
      do
         test "$i" == "$j" && continue
         if  [[ "$j" == *"$i"* ]]
         then
               contained=true
               break
         fi
      done
      test "$contained" = false  && output="$output $i"
    done
    echo $output
}

###################################################################
# USUARIOS
###################################################################

#Obtenemos la lista de usuarios de la rama People y comprobamos si los hay repetidos.
usuarios=$(ldapsearch  -xLLL -h "$servidor" -b "ou=People,dc=instituto,dc=extremadura,dc=es" "uid" | grep uid: | cut -d" " -f2)
repetidos=$(echo $usuarios | tr " " "\n" | sort | uniq -d)
sinhome=""
badowner=""
badgrupo=""
cat /dev/null > /tmp/permisos.txt

for usuario in $usuarios
do
  echo -ne "Check $usuario \033[0K\r"
  ldapsearch  -xLLL -h "$servidor" -b "ou=People,dc=instituto,dc=extremadura,dc=es" "uid=$usuario"   uidNumber gidNumber homeDirectory > /tmp/nodo
  uid=$(cat /tmp/nodo | grep uidNumber:  |  cut -d" " -f2)
  gid=$(cat /tmp/nodo | grep gidNumber:  |  cut -d" " -f2)
  homedir=$(cat /tmp/nodo | grep homeDirectory:  |  cut -d" " -f2)
  #¿Existe el directorio home del usuario?
  # AVISO: para que esta parte funcione el script debe ejecutarse en el servidor NFS donde está los homes de los usuarios. 
  if [ -d $homedir ]
  then
     uid_file=$(stat -c %u "$homedir")
     gid_file=$(stat -c %g "$homedir")
     perm_file=$(stat -c %A "$homedir")
     #¿El propietario efectivo del home es el usuario?  
     if [ $uid_file -ne $uid -o $gid_file -ne $gid ]
     then
         badowner="$homedir $badowner"
     fi
  else
     sinhome="$homedir $sinhome"
  fi
  #¿El usuario tiene grupo privado?
  gidgroup=$(ldapsearch  -xLLL -h "$servidor" -b "ou=Group,dc=instituto,dc=extremadura,dc=es" "cn=$usuario" gidNumber  | grep gidNumber: | cut -d" " -f2)
  test -z "$gidgroup" && gidgroup=-1
  #¿Tiene el gid correcto el grupo privado?
  if [ $gid -ne $gidgroup ]
  then
     badgroup="$usuario $badgroup"
  fi
  echo "$perm_file $homedir">> /tmp/permisos.txt
done
echo -ne "Check                                        \033[0K\r"
echo ""
mensaje "Rama People -> Usuarios repetidos:" "$repetidos"
mensaje "NFS -> Usuarios sin directorio home creado:" "$sinhome"
mensaje "NFS -> Homes con propietarios incorrectos:" "$badowner"
mensaje "Rama People/Group -> Usuarios sin grupo privado o con gidNumber incorrecto:" "$badgroup"
variantes_permisos=$(cat /tmp/permisos.txt | cut -d" " -f1 | sort | uniq | tr "\n" " ")

pass=$1
if [ -z "$pass" ]
then
   echo "Rama People -> Alumnos sin foto: No ha indicado contraseña de admin de ldap como parámetro del script. No se puede extraer esa información."
else
    #Buscamos usuarios alumno sin foto
    sin_foto=$(ldapsearch  -xLLL -h "$servidor"  -D "cn=admin,ou=People,dc=instituto,dc=extremadura,dc=es" -w $pass -b "ou=People,dc=instituto,dc=extremadura,dc=es" "(&(objectClass=inetOrgPerson)(!(jpegPhoto=*)))" "homeDirectory"  | grep "/home/alumnos" | cut -d"/" -f4 | tr "\n" " ")
    mensaje "Rama People -> Alumnos sin foto:" "$sin_foto" true
fi

###################################################################
# NFS-HOMES
###################################################################

# AVISO: para que esta parte funcione el script debe ejecutarse en el servidor NFS donde está los homes de los usuarios. 
#No hay un estándar consensuado sobre que permisos son los correctos para los homes de los usuarios, asi que recopilamos todas las variantes encontradas
echo "NFS -> Combinaciones de permisos encontrados en homes:"
max_permisos=0 #Buscamos el permiso mas frecuente de los homes
for perm in $variantes_permisos
do
    num_dir=$(grep "$perm" /tmp/permisos.txt |wc -l)
    test $num_dir -gt $max_permisos && max_permisos=$num_dir
done
#Mostramos cada variante de permisos junto con los homes que los tienen.
#Excepto para el grupo mayoritario, que no se listan los homes
for perm in $variantes_permisos
do
    num_dir=$(grep "$perm" /tmp/permisos.txt |wc -l)
    echo "    $perm -> $num_dir aparición(es)"
    if [ $num_dir -ne $max_permisos ]
    then
       homes_permisos=$(grep $perm /tmp/permisos.txt | cut -d" " -f2 | sort | tr "\n" " ")
       echo -e "\t\t$homes_permisos" | fmt
    fi
done
real_homes=$(ls -d /home/alumnos/* /home/profesor/*  /home/staff/*)
#Homes que existen en el disco, pero no hay usuario ldap para ellos
orphan_homes=""
for homedir in $real_homes
do
   if ! grep " $homedir$" /tmp/permisos.txt > /dev/null
   then
      test "$homedir" == "/home/profesor/dpto" || orphan_homes="$homedir $orphan_homes"
   fi
done
mensaje "NFS -> Homes huérfanos:" "$orphan_homes" true

###################################################################
# GRUPOS
###################################################################

#Lista de grupos privados de usuarios
privategroup=$(ldapsearch -xLLL -h "$servidor" -b "ou=Group,dc=instituto,dc=extremadura,dc=es" "groupType=private" | grep cn: | cut -d" " -f2)
badgroup=""
for grupo in $privategroup
do
  ldapsearch  -xLLL -h "$servidor" -b "ou=Group,dc=instituto,dc=extremadura,dc=es" "cn=$grupo" cn gidNumber > /tmp/nodo
  cn=$(cat /tmp/nodo | grep cn:  |  cut -d" " -f2)
  gid=$(cat /tmp/nodo | grep gidNumber:  |  cut -d" " -f2)
  giduser=$(ldapsearch  -xLLL -h "$servidor" -b "ou=People,dc=instituto,dc=extremadura,dc=es" "uid=$grupo" gidNumber  | grep gidNumber: | cut -d" " -f2)
  #Miramos si el gid coincide con el gid que hay en el nodo del usuario o si el usuario no existe en la rama de usuarios
  test -z "$giduser" && giduser=-1
  if [ $gid -ne $giduser ]
  then
     badgroup="$grupo $badgroup"
  fi
done
mensaje "Rama Group -> grupos privados sin usuario asociado o con gidNumber diferente al de la rama People:"  "$badgroup" true

#Lista de grupos NO privados
grupos=$(ldapsearch  -xLLL -h "$servidor" -b "ou=Group,dc=instituto,dc=extremadura,dc=es"  "(!(groupType=private))" "cn" | grep cn: | cut -d" " -f2)
repetidos=$(echo $grupos | tr " " "\n" | sort | uniq -d)
#Buscamos grupos repetidos
mensaje "Rama Group -> grupos repetidos: $repetidos" "$repetidos"

badmembers=""
emptygroup=""
for grupo in $grupos
do
  ldapsearch  -xLLL -h "$servidor" -b "ou=Group,dc=instituto,dc=extremadura,dc=es" "cn=$grupo" cn member memberUid groupType > /tmp/nodo
  cn=$(cat /tmp/nodo | grep cn:  |  cut -d" " -f2)
  member=$(cat /tmp/nodo | grep "member: "  |  cut -d" " -f2)
  memberUid=$(cat /tmp/nodo | grep "memberUid: "  |  cut -d" " -f2)
  groupType=$(cat /tmp/nodo | grep groupType:  |  cut -d" " -f2)
  echo $member | tr " " "\n" > /tmp/members
  sed -i '/^$/d' /tmp/members
  #Si el grupo no tiene miembros 
  if [ -z "$member" -o -z "$memberUid" ]
  then
     emptygroup="$grupo $emptygroup"
  else
     #Procesamos usuarios de memberUid
     for usuario in $memberUid #Si tiene miembros comprobamos si está en People, y si cada miembro está en member y en memberUid, sin que sobre ninguno
     do
        datos=$(ldapsearch  -xLLL -h "$servidor" -b "ou=People,dc=instituto,dc=extremadura,dc=es" "uid=$usuario"  "uid")
        #Si el usuario no está en la rama People
        test -z "$datos" && badmembers="$grupo:$usuario $badmembers"
        #Si no está en members
        if ! grep "^uid=$usuario," /tmp/members  > /dev/null
        then
           badmembers="$grupo:$usuario $badmembers"
        else #Borramos los usuarios que vamos encontrando de members
           sed -i "/^uid=$usuario,/d" /tmp/members
        fi
     done
     #Al acabar el proceso, los usuarios que quedan en member están descolgados y lo señalamos
     for usuario in $(cat /tmp/members) 
     do
          badmembers="$grupo:$usuario $badmembers"
     done
  fi
done
mensaje "Rama Group -> grupos vacios:" "$emptygroup" true
mensaje "Rama Group -> grupos con usuarios no existentes:" "$badmembers" true

###################################################################
# NETGROUPS
###################################################################

#Obtenemos la lista de Netgroups
netgroups=$(ldapsearch  -xLLL -h "$servidor" -b "ou=NetGroup,dc=instituto,dc=extremadura,dc=es" "objectClass=nisNetgroup" "cn" | grep "cn:" | cut -d" " -f2)
repetidos=$(echo $netgroups | tr " " "\n" | sort | uniq -d)
mensaje "Rama Netgroup -> netgroups repetidos:" "$repetidos"
emptynetgroup=""
badhosts=""
for grupo in $netgroups
do
  ldapsearch  -xLLL -h "$servidor" -b "ou=NetGroup,dc=instituto,dc=extremadura,dc=es" "cn=$grupo" cn nisNetgroupTriple memberNisNetgroup  > /tmp/nodo
  cn=$(cat /tmp/nodo | grep cn:  |  cut -d" " -f2)
  memberhost=$(cat /tmp/nodo | grep "nisNetgroupTriple: "  |  cut -d" " -f2 | tr -d "(" | cut -d"," -f1 )
  membergroup=$(cat /tmp/nodo | grep "memberNisNetgroup: "  |  cut -d" " -f2 | tr -d "(" | cut -d"," -f1 )
  if [ -z "$memberhost" -a -z "$membergroup" ] #Si estan vacios de miembros
  then
      emptynetgroup="$grupo $emptynetgroup"
  else
     #Verificamos que todos los hosts existen en la rama hosts
     if [ -n "$memberhost" ] 
     then
         for equipo in $memberhost
         do
            nodo=$(ldapsearch  -xLLL -h "$servidor" -b "ou=hosts,dc=instituto,dc=extremadura,dc=es" "dc=$equipo" dc)
            test -z "$nodo" &&  badhosts="$grupo:$equipo $badhosts"
         done
     fi
  fi
done
mensaje "Rama NetGroup -> grupos sin miembros:" "$emptynetgroup" true
mensaje "Rama NetGroup -> grupos con hosts no existentes en la rama Host:" "$badhosts" true

###################################################################
# DHCP_Config
###################################################################

#Lista de asignaciones mac-host en la rama Internal
dhcp=$(ldapsearch  -xLLL -h "$servidor" -b  "cn=INTERNAL,cn=DHCP Config,dc=instituto,dc=extremadura,dc=es" "objectClass=dhcpHost" "cn" | grep "cn:" | cut -d" " -f2)
#Hosts que tienen 2 o mas MAC asignadas (es una aviso, ya que un host puede tener 2 mac: mac ethernet y mac wifi)
repetidos=$(echo $dhcp | tr " " "\n" | sort | uniq -d | tr "\n" " ")
mensaje "Rama DHCP -> hosts con 2 o más MACs (revisar, no quiere decir que haya algo mal):"  "$repetidos"
baddhcp=""
badhosts=""
SAVEIFS=$IFS
IFS=$'\n' #El espacio en blanco no vale de separador en esta rama, el DN tiene espacios en blanco en medio
#Lista de hosts por dn:
dhcp=$(ldapsearch -o ldif-wrap=no -xLLL -h "$servidor" -b  "cn=INTERNAL,cn=DHCP Config,dc=instituto,dc=extremadura,dc=es" "objectClass=dhcpHost" "cn" |  grep "dn:"  | sed -e "s/^dn: //")
for dn in $dhcp
do
  ldapsearch  -xLLL -h "$servidor" -b "$dn" cn dhcpStatements dhcpHWAddress > /tmp/nodo
  cn=$(cat /tmp/nodo | grep cn:  |  cut -d" " -f2 | head -1)
  name=$(cat /tmp/nodo | grep "dhcpStatements:" | cut -d" " -f3)
  mac=$(cat /tmp/nodo | grep "dhcpHWAddress: " | cut -d" " -f3)
  #Si no coincide el nombre en cn con el nombre en dhcpStatements
  test "$cn" != "$name" && baddhcp="$name $baddhcp"
  nodo=$(ldapsearch  -xLLL -h "$servidor" -b "ou=hosts,dc=instituto,dc=extremadura,dc=es" "dc=$name" dc)
  #Si el host no está en la rama hosts
  test -z "$nodo" &&  badhosts="$name $badhosts"
done
IFS=$SAVEIFS
mensaje "Rama DHCP -> nodos donde no coinciden cn y dhcpStatements:" "$baddhcp" true
mensaje "Rama DHCP -> nodos con hosts no existentes en la rama Host:" "$badhosts" true

SAVEIFS=$IFS
IFS=$'\n' #El espacio en blanco no vale de separador en esta rama, el DN tiene espacios en blanco en medio
#Lista de nodos de dhcp con grupos de asignaciones dentro
dhcp=$(ldapsearch -o ldif-wrap=no -xLLL -h "$servidor" -b  "cn=DHCP Config,dc=instituto,dc=extremadura,dc=es" "objectClass=dhcpGroup" "cn" |  grep "dn:"  | sed -e "s/^dn: //")
echo "Rama DHCP -> grupos vacios:"
for dn in $dhcp
do
  miembros=$(ldapsearch  -xLLL -h "$servidor" -b "$dn" "objectClass=dhcpHost")
  #Si el grupo está vacio y no tiene asginaciones.
  test -z "$miembros" && echo -e "\t$dn"
done
IFS=$SAVEIFS
echo ""

#Obtenemos la lista de rangos DHCP, para mas tarde comprobar si alguna dirección fija entra en colisión con estos rangos.
rangos=$(ldapsearch -o ldif-wrap=no -xLLL -h "$servidor" -b  "cn=DHCP Config,dc=instituto,dc=extremadura,dc=es" "objectClass=dhcpSubNet" "dhcpRange" | grep "dhcpRange: " | cut -d" " -f2,3 | tr " " "-")
cat /dev/null > /tmp/ips-dhcp
if [ -e /usr/bin/prips ]  #Vemos si existe el comando prips para generar los rangos completos de IPs
then
   for rango in $rangos
   do
      ini=$(echo $rango | cut -d"-" -f1)
      fin=$(echo $rango | cut -d"-" -f2)
      prips $ini $fin >> /tmp/ips-dhcp #Genera todas las IPs que forman un rango desde la ip inicial y la final
   done
else
   echo "ALERTA: para poder comprobar si las IPs fijas colisionan con los rangos de IP de DHCP debe instalar el paquete 'prips'"
fi


#Buscar MAC repetidas
mac_repetidas=$(ldapsearch  -xLLL -h "$servidor" -b  "cn=DHCP Config,dc=instituto,dc=extremadura,dc=es" "objectClass=dhcpHost" "dhcpHWAddress" | grep "dhcpHWAddress: " | cut -d" " -f3 | sort | uniq -d)
dupmac=""
for mac in $mac_repetidas
do
   cn=$(ldapsearch  -xLLL -h "$servidor" -b  "cn=DHCP Config,dc=instituto,dc=extremadura,dc=es" "dhcpHWAddress=ethernet $mac" "cn" | grep "cn:" | cut -d" " -f2 | tr "\n" "/")
   dupmac="$mac:$cn $dupmac"   
done
mensaje "Rama DHCP -> IPs fijas que entran en conflicto con los rangos reservados para DHCP" "$dupmac" true


###################################################################
# HOSTS
###################################################################

#Lista de hosts den la rama hosts
hosts=$(ldapsearch  -xLLL -h "$servidor" -b "ou=hosts,dc=instituto,dc=extremadura,dc=es" "aRecord=*" | grep "dc:" | cut -d" " -f2)
#Detección de hosts repetidos
repetidos=$(echo $hosts | tr " " "\n" | sort | uniq -d)
badhost=""
noip=""
cat /dev/null > /tmp/ips
for equipo in $hosts
do
   ldapsearch  -xLLL -h "$servidor" -b "ou=hosts,dc=instituto,dc=extremadura,dc=es" "dc=$equipo" dc aRecord > /tmp/nodo
   dc=$(cat /tmp/nodo | grep "dc: "  |  cut -d" " -f2)
   ip=$(cat /tmp/nodo | grep "aRecord: "  |  cut -d" " -f2)
   echo $ip >> /tmp/ips
   #Si el nombre del host no coicide con el que hay en el nodo
   test "$dc" != "$equipo" && badhost="$dc $badhost"
   ip1=$(echo $ip | cut -d"." -f1)
   ip2=$(echo $ip | cut -d"." -f2)
   ip3=$(echo $ip | cut -d"." -f3)
   ip4=$(echo $ip | cut -d"." -f4)
   #Si la ip del host no está en la rama ARPA
   if ! ldapsearch  -xLLL -h "$servidor" -b "dc=$ip4,dc=$ip3,dc=$ip2,dc=$ip1,dc=in-addr,dc=arpa,ou=hosts,dc=instituto,dc=extremadura,dc=es" dc > /dev/null  2>&1
   then
      noip="$dc:$ip $noip"
   fi
done
mensaje "Rama Hosts -> Hosts -> nosts con nombre repetido:" "$repetidos"
mensaje "Rama Hosts -> Hosts -> hosts cuyo nombre en atributo dc no coincide:" "$badhost" true
mensaje "Rama Hosts -> Hosts -> host cuya IP no está en rama ARPA:" "$noip" true
repetidos=$(sort /tmp/ips | uniq -d)
mensaje "Rama Hosts -> Hosts -> ip repetidas:" "$repetidos" false

#Lista de IPs en la rama ARPA
ips=$(ldapsearch -o ldif-wrap=no -xLLL -h "$servidor" -b "dc=in-addr,dc=arpa,ou=hosts,dc=instituto,dc=extremadura,dc=es" "pTRRecord=*"  | grep dn:  | cut -d" " -f2)
badip=""
badname=""
cat /dev/null > /tmp/ips
for dc in $ips
do
   ldapsearch  -xLLL -h "$servidor" -b "$dc" associatedDomain pTRRecord > /tmp/nodo
   host=$(cat /tmp/nodo | grep "pTRRecord: "  |  cut -d" " -f2 | cut -d"." -f1)
   ip=$(cat /tmp/nodo | grep "associatedDomain: "  |  cut -d" " -f2)
   #La ip está al revés, la ordenamos
   ip1=$(echo $ip | cut -d"." -f4)
   ip2=$(echo $ip | cut -d"." -f3)
   ip3=$(echo $ip | cut -d"." -f2)
   ip4=$(echo $ip | cut -d"." -f1)
   ip="$ip1.$ip2.$ip3.$ip4"
   echo $ip >> /tmp/ips
   #Busco IP en rama hosts -> dominio
   dc=$(ldapsearch  -xLLL -h "$servidor" -b "ou=hosts,dc=instituto,dc=extremadura,dc=es" "aRecord=$ip" | grep "dc:" | cut -d" " -f2)
   if [ -z "$dc" ]
   then
      badip="$ip:$host $badip"
   else
      #Si no cooincide el nombre  del host en ambas ramas
      if [ "$host" != "$dc" ]
      then
          dc=$(echo $dc | tr " " "/")
          badname="$ip:$host:$dc $badname"
      fi 
   fi

done
mensaje "Rama Hosts -> Arpa -> IP no está en rama hosts:" "$badip" true
mensaje "Rama Hosts -> Arpa -> IP con nombre diferente en ambas ramas (ip:nombre arpa: nombre hosts):" "$badname" true

repetidos=$(sort /tmp/ips | uniq -d)
mensaje "Rama Hosts -> Arpa -> ip repetida:" "$repetidos" true

#Vamos a buscar las ramas/subredes ARPA vacias, sin IP por debajo.
badrama=""
ramasarpa=$(ldapsearch -o ldif-wrap=no -xLLL -h "$servidor" -b "dc=in-addr,dc=arpa,ou=hosts,dc=instituto,dc=extremadura,dc=es" "(!(pTRRecord=*))"  | grep dn: | cut -d" " -f2)
for rama in $ramasarpa
do
   case $rama in # Las ramas 0.X.Y.Z, 127.X.Y.Z, 255.X.Y.Z se saltan.
        "dc=0,dc=in-addr"* |  "dc=127,dc=in-addr"*  |  "dc=255,dc=in-addr"* )
            continue
        ;;
   esac
   nodos=$(ldapsearch  -xLLL -h "$servidor" -b "$rama"  pTRRecord | grep -i pTRRecord)
   #Si está vacía de IPs
   test  -z "$nodos" && badrama="$rama $badrama"
done
badrama=$(clean_duplicates "$badrama") #Quita los rangos IP contenidos dentro de otro rango de la lista.
mensaje "Rama Hosts -> Arpa -> Ramas sin IP definidas debajo:" "$badrama" true

#Mirar ips en /tmp/ips-dhcp (rangos) con /tmp/ips (ips encontradas)
ipshock=""
for ip in $(cat /tmp/ips)
do
  if grep "^$ip$" /tmp/ips-dhcp > /dev/null  2>&1
  then
      ipshock="$ip $ipshock"
  fi
done
mensaje "Rama Hosts -> IPs fijas que entran en conflicto con los rangos reservados para DHCP" "$ipshock" true
if [ "$ipshock" != "" ]
then
  mensaje "Rangos reservados para DHCP" "$rangos" 
fi

#Buscar nodos iphost obsoletos (deberían ser borrados) en rama ou=hosts,dc=instituto,dc=extremadura,dc=es
hosts_obsoletos=$(ldapsearch  -xLLL -h "$servidor" -b  "ou=hosts,dc=instituto,dc=extremadura,dc=es" "objectClass=iphost" "cn" | grep "dn:" | cut -d" " -f2)
mensaje "Rama Hosts -> nodos iphost obsoletos en rama ou=hosts,dc=instituto,dc=extremadura,dc=es:" "$hosts_obsoletos" true

exit 0
