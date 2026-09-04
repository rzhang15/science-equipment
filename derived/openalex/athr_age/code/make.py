import os
import subprocess
from gslab_make.move_sources import *
from gslab_make.run_program import *
from gslab_make.modify_dir import *
from gslab_make.write_logs import *
clear_dir(['../temp/'])
remove_dir(['../external/'])
paths = {'makelog' : '../output/make.log', 'external_dir' : '../external/'}
start_makelog(paths)

link_externals(paths, ['links.txt'])
subprocess.call('python build.py > ../output/build.log 2>&1', shell=True)
end_makelog(paths)
input('\n Press <Enter> to exit.')
