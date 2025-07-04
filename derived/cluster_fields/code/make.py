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
# BUILD.DO
#run_stata(paths, program = 'build.do')
#subprocess.call('Rscript --no-save build.R > ../output/build.Rout', shell=True)
end_makelog(paths)
input('\n Press <Enter> to exit.')
