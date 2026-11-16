// Root-owned helper: the sole writable target is the kernel CPU boost switch.
#include <fstream>
#include <iostream>
#include <string>
#include <unistd.h>
int main(int argc,char**argv){
 if(geteuid()!=0||argc!=3||std::string(argv[1])!="boost"||(std::string(argv[2])!="0"&&std::string(argv[2])!="1")){std::cerr<<"Expected authenticated boost 0 or boost 1\n";return 1;}
 const char*path="/sys/devices/system/cpu/cpufreq/boost";
 std::ofstream f(path);if(!f){std::cerr<<"CPU boost is unavailable\n";return 1;}f<<argv[2]<<'\n';f.close();if(!f){std::cerr<<"Kernel rejected boost change\n";return 1;}
 std::ifstream read(path);std::string value;read>>value;if(value!=argv[2]){std::cerr<<"CPU boost readback did not match\n";return 1;}std::cout<<"CPU boost verified: "<<value<<'\n';
}
