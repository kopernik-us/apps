# Apache Spark on Apache Hadoop, configured from the environment a kopernik.us cluster app gives its containers.
#
# A Spark cluster is a Hadoop cluster whose YARN runs Spark's executors, so every node runs this one image: the
# Hadoop daemons as the hadoop app's image runs them, the Spark history server on a master, and Spark itself wherever
# a job's driver or executors are started. It is built on the upstream Hadoop image as the hadoop app's is, with that
# app's entry point and format step copied beside Spark's own, so this directory is all that goes into the image.
#
# Spark 4.3.0 is built against Hadoop 3.5.0, so the Hadoop client it bundles is the release the cluster runs.
FROM apache/hadoop:3.5.0

USER root
# The release is checked against the SHA-512 Apache published for it, pinned here rather than downloaded beside it, so
# an archive altered on its way to the build fails the build instead of becoming the image.
RUN curl -fsSL -o /tmp/spark.tgz https://archive.apache.org/dist/spark/spark-4.3.0/spark-4.3.0-bin-hadoop3.tgz \
    && echo "51a2473d09c74b6b755d3c4158275922fe4fed9c3801d9e48ade6083dc03b45693274020fe0fcf2be2a607a6a828f7159f78609ef913049e98c1882d2d0aab5f  /tmp/spark.tgz" \
        | sha512sum -c - \
    && mkdir /opt/spark \
    && tar -xzf /tmp/spark.tgz -C /opt/spark --strip-components=1 \
    && rm /tmp/spark.tgz \
    # The shuffle service runs inside the node manager, which loads it from its own classpath.
    && cp /opt/spark/yarn/spark-4.3.0-yarn-shuffle.jar /opt/hadoop/share/hadoop/yarn/lib/ \
    # Spark reads spark-defaults.conf, and the entry point's settings are written as spark-defaults.properties into
    # the Hadoop configuration directory, in a format Spark reads alike.
    && ln -s /opt/hadoop/etc/hadoop/spark-defaults.properties /opt/spark/conf/spark-defaults.conf

# PySpark's drivers and executors run one Python, kept apart from the system's in /opt/python: JupyterLab for the master's
# notebooks, and the libraries a notebook's driver and its executors need alike, which is why every node carries it.
# Spark's own Python package is the one in /opt/spark, so the driver is always the release the cluster runs.
COPY requirements.txt /tmp/requirements.txt
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3-venv \
    && rm -rf /var/lib/apt/lists/* \
    && python3 -m venv /opt/python \
    && /opt/python/bin/pip install --no-cache-dir -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt \
    && site="$(/opt/python/bin/python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')" \
    && { echo /opt/spark/python; ls /opt/spark/python/lib/py4j-*-src.zip; } > "$site/spark.pth"

COPY entrypoint.sh format-hdfs.sh /opt/kopernik/
COPY spark-entrypoint.sh start-history-server.sh start-jupyter.sh spark-session.py /opt/kopernik/
COPY pyspark-kernel.json /opt/python/share/jupyter/kernels/pyspark/kernel.json
# The data directories are the defaults the entry point configures, and the notebooks' own. They are created here so
# that a node whose volume is mounted elsewhere, or not at all, still starts: HDFS refuses to run on a path it cannot
# write, and the image's own user is not the one Docker would create a missing bind mount for.
RUN chmod 0755 /opt/kopernik/entrypoint.sh /opt/kopernik/format-hdfs.sh /opt/kopernik/spark-entrypoint.sh \
        /opt/kopernik/start-history-server.sh /opt/kopernik/start-jupyter.sh \
    && mkdir -p /data/namenode /data/datanode /data/notebooks \
    && chown -R hadoop:users /data

# What a shell opened in a container needs to submit a job: Spark on the path, the cluster's Hadoop configuration, and
# the Python the image carries for PySpark's drivers and executors alike.
ENV SPARK_HOME=/opt/spark \
    HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop \
    PATH=/opt/spark/bin:${PATH} \
    PYSPARK_PYTHON=/opt/python/bin/python

USER hadoop

ENTRYPOINT ["/usr/local/bin/dumb-init", "--", "/opt/kopernik/spark-entrypoint.sh"]
