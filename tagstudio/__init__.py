# allow local module files as import
# https://github.com/python-poetry/poetry/issues/3928#issuecomment-1399313433
import os, sys; sys.path.append(os.path.dirname(os.path.realpath(__file__)))
