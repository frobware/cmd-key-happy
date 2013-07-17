# distutils: language = c++
# distutils: sources = CmdKeyHappy.mm

from libcpp.vector cimport vector
from libcpp.string cimport string
from libcpp.set cimport set
from libcpp cimport bool

cdef extern from "CmdKeyHappy.hpp" namespace "frobware":
	cdef cppclass CmdKeyHappy:
		void registerProcess(string appname)
		void addKeyExclusion(string appname, string keySeq)

cdef extern from "CmdKeyHappy.hpp" namespace "frobware::CmdKeyHappy":
	CmdKeyHappy* Instance()

def Register(name, *args):
	Instance().registerProcess(name)
	for a in args:
		Instance().addKeyExclusion(name, a)
