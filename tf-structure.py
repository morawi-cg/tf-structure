def get_nested(data, *args):
if args and data:
   element = args[0]    
   if element:
       value = data.get(element)
       return value if len(args) == 1 else get_nested(value, *args[1:])

dct={"a":{"b":{"c": d}}}
get_nested(dct, "a", "b", "c")
