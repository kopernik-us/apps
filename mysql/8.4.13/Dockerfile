# MySQL, sized to the share of the machine a kopernik.us container app gives it.
#
# The upstream image reads its credentials and its first database from the environment, which is all the template
# needs to configure, but sizes nothing to the machine it runs on. This image adds an entry point which sizes the
# InnoDB buffer pool from K_US_CONTAINER_MEMORY_MB on every start, and then hands over to the upstream entry point
# unchanged.
FROM mysql:8.4.13

COPY entrypoint.sh /opt/kopernik/
RUN chmod 0755 /opt/kopernik/entrypoint.sh

# The data directory, /var/lib/mysql, is the upstream image's: it declares the directory, and its entry point gives
# it to the mysql user on every start, so a bind mount Docker creates for it as root is writable by the server too.

# Setting an entry point clears the command the base image set, so it is set again: the server, which the upstream
# entry point runs as the mysql user.
ENTRYPOINT ["/opt/kopernik/entrypoint.sh"]
CMD ["mysqld"]
