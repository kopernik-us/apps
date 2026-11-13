# Apache Hadoop, configured from the environment a kopernik.us cluster app gives its containers.
#
# The upstream image already turns environment variables named <FILE>.<EXT>_<property> into Hadoop
# configuration, but the values this cluster needs cannot be written as one. A namenode's address is
# hdfs://<the cluster's first master>:8020, and the name of that master is known only on the machine: the
# environment file reaches Docker unexpanded, so a value naming another variable would arrive literally.
#
# So this image composes those values where the variables have values, and then hands over to the upstream
# entry point unchanged, which writes the XML and runs the daemon it was asked for.
FROM apache/hadoop:3.5.0

USER root
COPY entrypoint.sh format-hdfs.sh /opt/kopernik/
# The data directories are the defaults the entry point configures. They are created here so that a node
# whose volume is mounted elsewhere, or not at all, still starts: HDFS refuses to run on a path it cannot
# write, and the image's own user is not the one Docker would create a missing bind mount for.
RUN chmod 0755 /opt/kopernik/entrypoint.sh /opt/kopernik/format-hdfs.sh \
    && mkdir -p /data/namenode /data/datanode \
    && chown -R hadoop:users /data
USER hadoop

ENTRYPOINT ["/usr/local/bin/dumb-init", "--", "/opt/kopernik/entrypoint.sh"]
