# Introduction
Stained glass is a Windows testlab deployment tool configures to run directly on the hypervisor. It is a project build by UvA students for research in close colebaration with outflank.nl. It is meant to be a tool for software testing, penetration testing and malware research. It deploys disks directly from the hypervisor instead of traditional testlab tools like SCCM, WDS or puppet. 

So what does Stained-Glas do? It deploys a realistic testlab in one click and go, all it takes is a defined lab in a XML file. This includes:
  * User files
  * Working AD
  * AD users
  * Software on clients
  * Software on servers
  * Any number of servers
  * Any number of Clients

# How does it work?

Stained-Glass is based on a new deployment model specified in [research paper here]. It directly deploys disks to the VM by using differencing disks and sysprep. It is completely build using powershell and a bit of BAT magic. All scripts are invoked from the init_server.ps1 file in the scripts/hyper-v/ folder. If you want to add your own installation script somewhere in the process there then you should place it there.

Exchange installation is done seperately and can be removed from the script by the invocation line in init_servers.ps1. Exchange installation as is is incredably dodgy and not stable since it tends to fail every now and then for fun. Every lab should have its own subnet in the 10.0.x.0/24 subnet. This allows for a total of 255 labs defined. 
  

# How do i make it work?

The tool requires 2 things to function:

1. A lab defined in configs/labs_config.xml. A example can be found there. It expects a labname and some domain names there
2. A image to deploy from. The images are build by using sysprep. If you want to add a clean windows image take the following steps:
  1. install windows on a VM using the .vhdx disk format
  2. Enable [Powershell remoting](https://msdn.microsoft.com/en-us/powershell/reference/4.0/microsoft.powershell.core/enable-psremoting)
  3. Add a [unnattend.xml](https://technet.microsoft.com/en-us/library/c026170e-40ef-4191-98dd-0b9835bfa580)
  4. [Sysprep](https://technet.microsoft.com/en-us/library/cc721940(v=ws.10).aspx) the image by using the following command: C:/Windows/System32/Sysprep/Sysprep.exe /generalize /oobe /shutdown /unattend:path-to-your-unattend.xml

# What else can it do in the future?

We are planning some sweet features for the future, including:

  * Log file generation on windows
  * Mounting of department folders
  * Content generation on local client machines (think desktop, downloads etc)
  * Automated image library
  * Domain forest configuration in a more dynamic manner
  * Increasing speed and performance

# Contact

You can email me at fons.mijnen[at]os3.nl

# Licensing

Copyright 2017 Fons Mijnen, Vincent van Dongen, Outflank, UvA

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

