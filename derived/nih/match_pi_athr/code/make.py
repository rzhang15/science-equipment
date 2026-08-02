#****************************************************
# GET LIBRARY
#****************************************************
import os
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

import subprocess
# MATCH.PY: build pi_name -> athr_id crosswalk (institution-blocked fuzzy match)
subprocess.call('python match.py > ../output/match.log 2>&1', shell=True)

# BUILD.DO: apply crosswalk to every athr panel variant
run_stata(paths, program = 'build.do')

end_makelog(paths)
input('\n Press <Enter> to exit.')
