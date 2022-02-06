package jstack;

#if (debug || JSTACK_FORCE)

#if js
typedef JStack = jstack.js.JStack;
#elseif php
typedef JStack = jstack.php7.JStack;
#end

#end