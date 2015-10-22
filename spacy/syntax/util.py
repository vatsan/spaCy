from os import path
import json
import sys

def unicode_to_ascii(d):
    """
        Convert unicode keys to ascii recursively:
        http://stackoverflow.com/questions/1254454/fastest-way-to-convert-a-dicts-keys-values-from-unicode-to-str
    """
    if not isinstance(d, dict):
       return d
    return dict((str(k), unicode_to_ascii(v)) for k, v in d.items())

class Config(object):
    def __init__(self, **kwargs):
        for key, value in kwargs.items():
            setattr(self, key, value)

    def get(self, attr, default=None):
        return self.__dict__.get(attr, default)

    @classmethod
    def write(cls, model_dir, name, **kwargs):
    	open(path.join(model_dir, '%s.json' % name), 'w').write(json.dumps(kwargs))

    @classmethod
    def read(cls, model_dir, name):
        args = json.load(open(path.join(model_dir, '%s.json' % name)))
        # Workaround for Python 2.6.2 bug (http://bugs.python.org/issue2646) 
        if(sys.version_info[0] == 2 and sys.version_info[1] < 7 and sys.version_info[2] < 5):
            args = unicode_to_ascii(args)
        return cls(**args)
