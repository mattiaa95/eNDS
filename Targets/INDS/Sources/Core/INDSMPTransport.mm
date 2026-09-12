//
//  INDSMPTransport.mm
//  eNDS
//
//  Transport registry and the userdata → instance map. No networking.
//

#include "INDSMPTransport.h"

#include <mutex>
#include <unordered_map>

namespace eNDS {

namespace {
std::mutex gLock;
MPTransport *gTransport = nullptr;
std::unordered_map<void *, int> gInstances;
}

MPTransport *currentTransport() {
    std::lock_guard<std::mutex> guard(gLock);
    return gTransport;
}

void setCurrentTransport(MPTransport *transport) {
    std::lock_guard<std::mutex> guard(gLock);
    gTransport = transport;
}

int instanceForUserdata(void *userdata) {
    std::lock_guard<std::mutex> guard(gLock);
    auto it = gInstances.find(userdata);
    return it == gInstances.end() ? -1 : it->second;
}

void registerInstance(void *userdata, int inst) {
    std::lock_guard<std::mutex> guard(gLock);
    gInstances[userdata] = inst;
}

void unregisterInstance(void *userdata) {
    std::lock_guard<std::mutex> guard(gLock);
    gInstances.erase(userdata);
}

}
