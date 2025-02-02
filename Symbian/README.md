## EPOC32 release 2 to 5
Origin: Various
* Really old .sis files from before EPOC changed name to Symbian. They most likely only run on Psion and a few Ericsson devices. All files have been tested for valid header and content checksums.
## Symbian v6.0-v8.1b (S60v1 and S60v2)
Origin: Various
* Includes files for S80, S90 and UIQ based devices. All files have been tested for valid header and content checksums. Note that since .sis files in this format have no timestamp as such, the year has been taken from the certificate timestamps, and thus only present in files with certificates.
## Symbian v9.1+ (S60v3 and onwards)
Origin: Various
* Includes files for ^3, ^4, Anna and Belle devices. All files have been renamed with a slightly customized version of [https://github.com/NuruDashdamir/symbian-sis-renamer/] (Symbian SIS Renamer), which is known to be rather buggy. It has rejected quite a few valid files for me, so i am working on a new tool to do the job properly. Until then, this is what you get.
 
