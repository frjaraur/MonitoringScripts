import sys, getopt, yaml,os
from selenium import webdriver
from selenium.webdriver.common.keys import Keys
import time 

# browser = webdriver.Firefox()

# browser.get('http://www.google.com')
# assert 'Google' in browser.title

# elem = browser.find_element_by_name('q')  # Find the search box
# elem.send_keys('seleniumhq' + Keys.RETURN)
# time.sleep(10)
# browser.quit()


class Config:
    def __init__(self, configfile):
        with open(configfile) as f: configuration=yaml.safe_load(f)
        self.configuration=configuration
	
    def TestsConfig(self,root):
        return self.configuration[root]


def showhelp(vmyname):
   print ("HELP (" + vmyname + ")")
   sys.exit(2)

def exectest(vtesttasks):
    #Initialize Web Browser Driver
    browser = webdriver.Firefox()
    for vtask in vtesttasks:
        executetask(browser,vtask)

    browser.quit()

def executetask(vbrowser,vtask):
    print ("TASK --> "+vtask )
    tmp=vtask.split()
    command=tmp.pop(0)
    arguments=tmp
    print("command: "+command)
    print ("arguments: "+ str(arguments))
    if command == "open":
        vbrowser.get(arguments)
        return
    if command == "wait_for_page_to_load" :
        arguments = map(int, arguments)
        vbrowser.set_page_load_timeout(arguments)
        return

    if command == "close" :
        vbrowser.close()
        return




def main(argv):
    global debug, tasksfile
    tasksfile=""
    debug = False
    myname = os.path.basename(__file__)
    testsnames = list()
    testtasks = list()
    try:
      opts, args = getopt.getopt(argv, "Dht:", ["tasksfile=", "debug"])
    except getopt.GetoptError:
      showhelp(myname)

    for opt, arg in opts:
      if opt == '-h':
        showhelp(myname)
      elif opt in ("-D", "--debug"):
        debug = True
        print ("DEBUG MODE")
      elif opt in ("-t", "--tasksfile="):
        tasksfile=arg
      
    if tasksfile == '':
        print ("At least specify on tasksfile ... \n")
        showhelp(myname)
      
    tasksfile=Config(tasksfile)
    testsconfigs=tasksfile.TestsConfig("SELENIUM_TESTS")
    #print(testsconfigs)
    testsnames=testsconfigs.keys()
    for name in testsnames:
        print (name)
        print (testsconfigs[name])
        testtasks=testsconfigs[name]
        exectest(testtasks)
    
	
	
	
	
	
if __name__ == "__main__":
    main(sys.argv[1:])      
