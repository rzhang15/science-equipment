#***************************************************
# GET LIBRARY
#****************************************************
import os
import subprocess
from gslab_make.move_sources import *
from gslab_make.run_program import *
from gslab_make.modify_dir import *
from gslab_make.write_logs import *
#****************************************************
# MAKE.PY STARTS
clear_dir(['../output/', '../temp/'])
remove_dir(['../external/'])
paths = {'makelog' : '../output/make.log', 'external_dir' : '../external/'}
start_makelog(paths)

# MAKE LINKS
link_externals(paths, ['links.txt'])

# PARSE.PY: flatten the per-award JSON tree into csv
subprocess.call('python parse.py > ../output/parse.log 2>&1', shell=True)

# BUILD.DO: type, label and save the stata datasets
run_stata(paths, program = 'build.do')

end_makelog(paths)
input('\n Press <Enter> to exit.')
