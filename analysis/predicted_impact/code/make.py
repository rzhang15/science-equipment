#****************************************************
# make.py  --  analysis/predicted_impact
#****************************************************
import os

from gslab_make.move_sources import *
from gslab_make.run_program import *
from gslab_make.modify_dir import *
from gslab_make.write_logs import *

clear_dir(['../output/', '../temp/', '../output_local/'])
remove_dir(['../external/'])
paths = {'makelog': '../output/make.log', 'external_dir': '../external/'}
start_makelog(paths)
link_externals(paths, ['links.txt'])

run_stata(paths, program='analysis.do')

end_makelog(paths)
