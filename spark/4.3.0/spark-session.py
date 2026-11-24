"""Starts the Spark session of a PySpark notebook when its first cell runs, as `spark` and `sc`.

The session starts on the first cell rather than with the kernel, because starting it waits for YARN to run the
session's application master, which on a busy cluster takes longer than JupyterLab waits for a kernel to answer. Its
driver runs in this kernel, in client mode, and its executors in YARN on the core nodes.
"""

import os

from IPython import get_ipython


def _start_spark_session(_info):
    shell.events.unregister("pre_run_cell", _start_spark_session)
    from pyspark.sql import SparkSession

    # The notebook's name tells its application from the others in YARN and in the history server.
    name = os.path.splitext(os.path.basename(os.environ.get("JPY_SESSION_NAME", "")))[0] or "notebook"
    print("Starting the Spark session; the first time, YARN takes a little while to start its application.")
    spark = SparkSession.builder.appName(name).getOrCreate()
    shell.user_ns.update(spark=spark, sc=spark.sparkContext)


shell = get_ipython()
shell.events.register("pre_run_cell", _start_spark_session)
