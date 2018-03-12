PROJNAME= luaopenbusaudit
LIBNAME= $(PROJNAME)

SRC= $(PRELOAD_DIR)/$(LIBNAME).c

LUADIR= ../lua
LUASRC= \
	$(LUADIR)/openbus/core/audit/Agent.lua \
	$(LUADIR)/openbus/core/audit/Event.lua \
	$(LUADIR)/openbus/util/http.lua \
	$(LUADIR)/socket.lua \
	$(LUADIR)/socket/http.lua \
	$(LUADIR)/socket/url.lua \
	$(LUADIR)/json.lua \
	$(LUADIR)/base64.lua \
	$(LUADIR)/ltn12.lua

include base.mak
