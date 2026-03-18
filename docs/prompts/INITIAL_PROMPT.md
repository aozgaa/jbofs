This machine has a bunch of nvme drives that I think are currently sitting idle, not even mounted.
Help me:
1. identify them
2. pick a good filesystem to use with them -- ext4, xfs, zfs, ... ?
3. develop a plan / sequence of scripts (bash and/or python) to set it up (but do not actually run them, maybe include a
   dry run mode)
4. include fio benchmark scripts

I plan to use these disks to store pure data -- think pcap files.
I like a JBOD-like arrangement.
Treat this prompt as historical context for the storage project, not as the current `jbofs` contract.
Ideally I can force files onto a particular disk whenever I need to optimize IO.

The workload is iterating through pcap files, usually start to finish (I will stripe pcaps, eg by symbol in a hive-like
partition, where needed).

Please summarize the entire design and how to invoke scripts to reproduce any analytics/reports in README.md
