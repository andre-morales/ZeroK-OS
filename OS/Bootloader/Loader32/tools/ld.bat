@echo off
pushd %cd%
cd %~dp0\..
"..\..\..\Tools/GCC/bin/i386-elf-ld.exe" %*
popd