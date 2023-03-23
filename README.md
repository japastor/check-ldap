# check-ldap
Script bash que busca inconsistencias y datos duplicados en un árbol ldap.

Importante:
* En la variable "servidor" del comienzo del script pondremos la IP del servidor ldap a chequear.
* Para comprobar los homes de los usuarios el script de debe ejecutarse en el servidor NFS.
* Admite un parámetro opcional: la contraseña de ldap. Si lo indicamos se comprobará además que alumnos no tienen foto en su registro.

Comprobaciones que realiza:
