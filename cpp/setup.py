from distutils.extension import Extension
from distutils.core import setup
from Cython.Distutils import build_ext
from Cython.Build import cythonize

# setup(ext_modules = cythonize("*.pyx"),
#       )

lib_extension = Extension('libext', sources=['foo.c'], language='c++')

setup(name = "CMD_KEY_HAPPY",
      cmdclass = {'build_ext': build_ext},
      ext_modules = cythonize(["*.pyx"]))

