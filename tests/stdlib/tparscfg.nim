import parsecfg

## Creating a configuration file.
var dict1=newConfig()
dict1.setSectionKey("","charset","utf-8")
dict1.setSectionKey("Package","name","hello")
dict1.setSectionKey("Package","--threads","on")
dict1.setSectionKey("Author","name","lihf8515")
dict1.setSectionKey("Author","qq","10214028")
dict1.setSectionKey("Author","email","lihaifeng@wxm.com")
dict1.writeConfig("config.ini")

## Reading a configuration file.
var dict2 = loadConfig("config.ini")
var charset = dict2.getSectionValue("","charset")
var threads = dict2.getSectionValue("Package","--threads")
var pname = dict2.getSectionValue("Package","name")
var name = dict2.getSectionValue("Author","name")
var qq = dict2.getSectionValue("Author","qq")
var email = dict2.getSectionValue("Author","email")
echo charset
echo threads
echo pname
echo name
echo qq
echo email

## Modifying a configuration file.
var dict3 = loadConfig("config.ini")
dict3.setSectionKey("Author","name","lhf")
dict3.writeConfig("config.ini")

## Deleting a section key in a configuration file.
var dict4 = loadConfig("config.ini")
dict4.delSectionKey("Author","email")
dict4.writeConfig("config.ini")

