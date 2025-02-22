#!/usr/bin/python3
##################################
#
# regression-wally
# David_Harris@Hmc.edu 25 January 2021
# Modified by Jarred Allen <jaallen@g.hmc.edu>
#
# Run a regression with multiple configurations in parallel and exit with
# non-zero status code if an error happened, as well as printing human-readable
# output.
#
##################################
import sys,os,shutil

class bcolors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

from collections import namedtuple
regressionDir = os.path.dirname(os.path.abspath(__file__))
os.chdir(regressionDir)

TestCase = namedtuple("TestCase", ['name', 'variant', 'cmd', 'grepstr'])
# name:     the name of this test configuration (used in printing human-readable
#           output and picking logfile names)
# cmd:      the command to run to test (should include the logfile as '{}', and
#           the command needs to write to that file)
# grepstr:  the string to grep through the log file for. The test succeeds iff
#           grep finds that string in the logfile (is used by grep, so it may
#           be any pattern grep accepts, see `man 1 grep` for more info).

# edit this list to add more test cases
configs = [
    TestCase(
        name="lints",
        variant="all",
        cmd="./lint-wally | tee {}",
        grepstr="All lints run with no errors or warnings"
    )
]

bpdSize = [6, 8, 10, 12, 14, 16]
bpdType = ['twobit', 'gshare', 'global', 'gshare_basic', 'global_basic']
for CurrBPType in bpdType:
    for CurrBPSize in bpdSize:
        name = CurrBPType+str(CurrBPSize)
        configOptions = "+define+INSTR_CLASS_PRED=0 +define+BPRED_TYPE=\"BP_" + CurrBPType.upper() + "\" +define+BPRED_SIZE=" + str(CurrBPSize)
        tc = TestCase(
            name=name,
            variant="rv32gc",
            cmd="vsim > {} -c <<!\ndo wally-batch.do  rv32gc configOptions " + name + " embench " + configOptions,
            grepstr="")
        configs.append(tc)

import os
from multiprocessing import Pool, TimeoutError

def search_log_for_text(text, logfile):
    """Search through the given log file for text, returning True if it is found or False if it is not"""
    grepcmd = "grep -e '%s' '%s' > /dev/null" % (text, logfile)
    return os.system(grepcmd) == 0

def run_test_case(config):
    """Run the given test case, and return 0 if the test suceeds and 1 if it fails"""
    logname = "logs/"+config.variant+"_"+config.name+".log"
    cmd = config.cmd.format(logname)
    print(cmd)
    os.chdir(regressionDir)
    os.system(cmd)
    if search_log_for_text(config.grepstr, logname):
        print(f"{bcolors.OKGREEN}%s_%s: Success{bcolors.ENDC}" % (config.variant, config.name))
        return 0
    else:
        print(f"{bcolors.FAIL}%s_%s: Failures detected in output{bcolors.ENDC}" % (config.variant, config.name))
        print("  Check %s" % logname)
        return 1

def main():
    """Run the tests and count the failures"""
    TIMEOUT_DUR = 10800 # 3 hours

    global configs
    try:
        os.chdir(regressionDir)
        os.mkdir("logs")
        #print(os.getcwd())
        #print(regressionDir)
    except:
        pass
    try:
        shutil.rmtree("wkdir")
    except:
        pass
    finally:
        os.mkdir("wkdir")
 
    if '-makeTests' in sys.argv:
        os.chdir(regressionDir)
        os.system('./make-tests.sh | tee ./logs/make-tests.log')

    # Scale the number of concurrent processes to the number of test cases, but
    # max out at a limited number of concurrent processes to not overwhelm the system
    with Pool(processes=min(len(configs),40)) as pool:
       num_fail = 0
       results = {}
       for config in configs:
           results[config] = pool.apply_async(run_test_case,(config,))
       for (config,result) in results.items():
           try:
             num_fail+=result.get(timeout=TIMEOUT_DUR)
           except TimeoutError:
             num_fail+=1
             print(f"{bcolors.FAIL}%s_%s: Timeout - runtime exceeded %d seconds{bcolors.ENDC}" % (config.variant, config.name, TIMEOUT_DUR))

    # Count the number of failures
    if num_fail:
        print(f"{bcolors.FAIL}Regression failed with %s failed configurations{bcolors.ENDC}" % num_fail)
    else:
        print(f"{bcolors.OKGREEN}SUCCESS! All tests ran without failures{bcolors.ENDC}")
    return num_fail

if __name__ == '__main__':
    exit(main())
