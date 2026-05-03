#***************************************************
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
os.mkdir('../output/figures/')
remove_dir(['../external/'])
paths = {'makelog' : '../output/make.log', 'external_dir' : '../external/'}
start_makelog(paths)

# MAKE LINKS
link_externals(paths, ['links.txt'])
# RUN PLACEBO MATCH (R) THEN BUILD MATCHED PANELS (STATA)
run_r(paths, program = 'match_placebo.R')
run_stata(paths, program = 'build_placebo_panel.do')
end_makelog(paths)
input('\n Press <Enter> to exit.')
