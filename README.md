# check-ldap
Script bash que busca inconsistencias y datos duplicados en un árbol ldap.

Importante:
* En la variable "servidor" del comienzo del script pondremos la IP del servidor ldap a chequear.
* Para comprobar los homes de los usuarios el script de debe ejecutarse en el servidor NFS.
* Admite un parámetro opcional: la contraseña de ldap. Si lo indicamos se comprobará además que alumnos no tienen foto en su registro.

Algunas de las comprobaciones que realiza:
* Usuarios repetidos.
* Comprueba si existe el home del usuario en el servidor NFS y tiene el propietario correcto.
* Usuarios sin grupo privado.
* Alumnos sin foto.
* Homes en NFS huérfanos sin usuario en ldap.
* Permisos de los homes en NFS.
* Grupos privados sin usuario.
* Grupos repetidos.
* Grupos sin usuarios o con algunos usuarios no existentes.
* NetGroups repetidos.
* NetGroups vacios o con máquinas no existentes.
* Rama DHCP: nodos donde el nombre de máquina es incorrecto o no consistente.
* Rama DHCP: subramas vacías de asignaciones.
* Rama HDCP: MACs repetidas.
* Hosts repetidos.
* Hosts con inconsistencias en el nodo.
* Hosts cuya IP no está definida en la subrama ARPA.
* Hosts: IP Repetidas.
* Rama Hosts/Subrama ARPA: IP no definidas en subrama hosts, IP inconsistente, IP repetida.
* Rama Hosts/Subrama ARPA: subramas vacias.
* Hosts cuyas IP entran en conflicto con subrangos de asignación dinámica definidos en la rama DHCP.
* Rama hosts: hosts definidos en el primer nivel de esa rama siguiendo un estilo antiguo y que ya no son necesarios.

