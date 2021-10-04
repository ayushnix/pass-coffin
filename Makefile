PROG ?= coffin
PROGO ?= open
PROGC ?= close
PROGT ?= timer
PREFIX ?= /usr
DESTDIR ?=
LIBDIR ?= $(PREFIX)/lib
SYSTEM_EXTENSION_DIR ?= $(LIBDIR)/password-store/extensions
BASHCOMPDIR ?= /etc/bash_completion.d

all:
	@echo "pass-$(PROG) is a shell script and doesn't need to be compiled"
	@echo ""
	@echo "To install it, enter \"make install\""
	@echo ""

install:
	@install -vd "$(DESTDIR)$(SYSTEM_EXTENSION_DIR)" "$(DESTDIR)$(BASHCOMPDIR)"
	@install -vm 0755 $(PROG).bash "$(DESTDIR)$(SYSTEM_EXTENSION_DIR)/$(PROG).bash"
	@install -vm 0755 $(PROGO).bash "$(DESTDIR)$(SYSTEM_EXTENSION_DIR)/$(PROGO).bash"
	@install -vm 0755 $(PROGC).bash "$(DESTDIR)$(SYSTEM_EXTENSION_DIR)/$(PROGC).bash"
	@install -vm 0755 $(PROGT).bash "$(DESTDIR)$(SYSTEM_EXTENSION_DIR)/$(PROGT).bash"
	@install -vm 0644 "completion/pass-$(PROG).bash-completion" "$(DESTDIR)$(BASHCOMPDIR)/pass-$(PROG)"
	@echo
	@echo "pass-$(PROG) has been installed succesfully"
	@echo

uninstall:
	@rm -vf \
		"$(DESTDIR)$(SYSTEM_EXTENSION_DIR)/$(PROG).bash" \
		"$(DESTDIR)$(SYSTEM_EXTENSION_DIR)/$(PROGO).bash" \
		"$(DESTDIR)$(SYSTEM_EXTENSION_DIR)/$(PROGC).bash" \
		"$(DESTDIR)$(SYSTEM_EXTENSION_DIR)/$(PROGT).bash" \
		"$(DESTDIR)$(BASHCOMPDIR)/pass-$(PROG)"

.PHONY: install uninstall
