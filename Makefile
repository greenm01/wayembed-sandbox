CXX ?= c++
CC ?= cc
WAYLAND_SCANNER ?= wayland-scanner
WAYEMBED_DIR ?= /home/niltempus/dev/wayembed
NILAMP_DIR ?= /home/niltempus/dev/nilamp
VST3SDK_DIR ?= $(NILAMP_DIR)/third_party/vst3sdk

BUILD_DIR := build
BIN_DIR := bin
XDG_XML := /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml
XDG_HEADER := $(BUILD_DIR)/xdg-shell-client-protocol.h
XDG_CODE := $(BUILD_DIR)/xdg-shell-protocol.c
XDG_OBJ := $(BUILD_DIR)/xdg-shell-protocol.o
VST3_SMOKE_OBJ := $(BUILD_DIR)/vst3_host_smoke.o
VST3_SMOKE := $(BIN_DIR)/wayembed-vst3-host-smoke

CXXFLAGS ?= -std=c++17 -O2 -Wall -Wextra -Wpedantic -Werror
CFLAGS ?= -std=c11 -O2 -Wall -Wextra -Wpedantic -Werror
CPPFLAGS += -I$(WAYEMBED_DIR)/include -I$(VST3SDK_DIR) -I$(BUILD_DIR)
LDLIBS += $(WAYEMBED_DIR)/zig-out/lib/libwayembed.a -lwayland-client -lwayland-server -ldl -lm

.PHONY: vst3-host-smoke clean-smoke

vst3-host-smoke: $(VST3_SMOKE)

$(BUILD_DIR) $(BIN_DIR):
	mkdir -p $@

$(XDG_HEADER): $(XDG_XML) | $(BUILD_DIR)
	$(WAYLAND_SCANNER) client-header $< $@

$(XDG_CODE): $(XDG_XML) | $(BUILD_DIR)
	$(WAYLAND_SCANNER) private-code $< $@

$(XDG_OBJ): $(XDG_CODE) $(XDG_HEADER) | $(BUILD_DIR)
	$(CC) $(CFLAGS) -I$(BUILD_DIR) -c $< -o $@

$(VST3_SMOKE_OBJ): tools/vst3_host_smoke.cpp $(XDG_HEADER) | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) -c $< -o $@

$(VST3_SMOKE): $(VST3_SMOKE_OBJ) $(XDG_OBJ) | $(BIN_DIR)
	$(CXX) $^ $(LDLIBS) -o $@

clean-smoke:
	rm -f $(VST3_SMOKE) $(VST3_SMOKE_OBJ) $(XDG_OBJ) $(XDG_HEADER) $(XDG_CODE)
