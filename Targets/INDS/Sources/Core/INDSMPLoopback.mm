//
//  INDSMPLoopback.mm
//  eNDS
//

#include "INDSMPLoopback.h"

#include <algorithm>
#include <cassert>
#include <cstring>

namespace eNDS {

namespace {
/// Un paquete caduca por tiempo EMULADO, no por reloj de pared: llega con el
/// microsegundo del emisor y se compara con el del receptor. Restar sin más
/// se da la vuelta cuando el receptor va por detrás, y un `u64` al revés es
/// enorme, así que todo pasaría el filtro justo cuando no debe.
bool isStale(uint64_t packetTimestamp, uint64_t now) {
    return now > kStaleWindow && packetTimestamp < (now - kStaleWindow);
}
}

void MPLoopback::begin(int inst) {
    if (inst < 0 || inst >= kMaxInstances) return;
    std::lock_guard<std::mutex> guard(_lock);
    _queues[inst] = Queue{};
    _queues[inst].connected = true;
}

void MPLoopback::end(int inst) {
    if (inst < 0 || inst >= kMaxInstances) return;
    {
        std::lock_guard<std::mutex> guard(_lock);
        _queues[inst] = Queue{};
        // `_lastHostID` NO se borra, aunque el que se vaya sea el propio host:
        // es lo único que le queda al cliente para distinguir "el host todavía
        // no ha mandado nada" de "el host se ha ido". Borrándolo,
        // `recvHostPacket` devolvía 0 en vez de -1 y el cliente se comía los
        // 25 ms de espera en cada frame esperando a alguien que no vuelve.
        // Si otro toma el relevo, el siguiente `sendCmd` lo actualiza.
    }
    // Al irse hay que despertar a los que estaban bloqueados esperándole, o
    // se quedan los 25 ms enteros parados por alguien que ya no va a contestar.
    _arrived.notify_all();
}

int MPLoopback::broadcast(int from, const uint8_t *data, int len, uint64_t timestamp,
                          bool toReplyQueue, bool fromHost, uint16_t aid) {
    if (from < 0 || from >= kMaxInstances || !data || len <= 0) return 0;
    {
        std::lock_guard<std::mutex> guard(_lock);
        if (!_queues[from].connected) return 0;
        Packet packet;
        packet.data.assign(data, data + len);
        packet.timestamp = timestamp;
        packet.sender = from;
        packet.aid = aid;
        packet.fromHost = fromHost;
        for (int i = 0; i < kMaxInstances; ++i) {
            if (i == from || !_queues[i].connected) continue;
            (toReplyQueue ? _queues[i].replies : _queues[i].packets).push_back(packet);
        }
    }
    _arrived.notify_all();
    return len;
}

int MPLoopback::sendPacket(int inst, const uint8_t *data, int len, uint64_t timestamp) {
    return broadcast(inst, data, len, timestamp, false, false, 0);
}

int MPLoopback::sendCmd(int inst, const uint8_t *data, int len, uint64_t timestamp) {
    {
        std::lock_guard<std::mutex> guard(_lock);
        _lastHostID = inst;   // manda CMD el que hace de host
    }
    return broadcast(inst, data, len, timestamp, false, true, 0);
}

int MPLoopback::sendAck(int inst, const uint8_t *data, int len, uint64_t timestamp) {
    return broadcast(inst, data, len, timestamp, false, true, 0);
}

int MPLoopback::sendReply(int inst, const uint8_t *data, int len, uint64_t timestamp, uint16_t aid) {
    return broadcast(inst, data, len, timestamp, true, false, aid);
}

int MPLoopback::receive(int inst, uint8_t *out, uint64_t *timestamp, bool hostOnly) {
    if (inst < 0 || inst >= kMaxInstances || !out) return 0;
    std::unique_lock<std::mutex> lock(_lock);
    if (!_queues[inst].connected) return 0;

    const auto deadline = std::chrono::steady_clock::now() +
                          std::chrono::milliseconds(kRecvTimeoutMs);
    auto &queue = _queues[inst].packets;
    for (;;) {
        while (!queue.empty()) {
            Packet packet = std::move(queue.front());
            queue.pop_front();
            if (hostOnly && !packet.fromHost) continue;   // no es para esta espera
            const int len = static_cast<int>(packet.data.size());
            std::memcpy(out, packet.data.data(), packet.data.size());
            if (timestamp) *timestamp = packet.timestamp;
            return len;
        }
        if (_arrived.wait_until(lock, deadline) == std::cv_status::timeout) return 0;
        if (!_queues[inst].connected) return 0;
    }
}

int MPLoopback::recvPacket(int inst, uint8_t *out, uint64_t *timestamp) {
    return receive(inst, out, timestamp, false);
}

int MPLoopback::recvHostPacket(int inst, uint8_t *out, uint64_t *timestamp) {
    {
        std::lock_guard<std::mutex> guard(_lock);
        // Igual que LocalMP: si el host se fue, -1 en vez de 0. El core
        // distingue "todavía no hay nada" de "ya no va a haber nada".
        if (_lastHostID >= 0 && !_queues[_lastHostID].connected) return -1;
    }
    return receive(inst, out, timestamp, true);
}

uint16_t MPLoopback::recvReplies(int inst, uint8_t *out, uint64_t timestamp, uint16_t aidmask) {
    if (inst < 0 || inst >= kMaxInstances || !out) return 0;
    std::unique_lock<std::mutex> lock(_lock);
    if (!_queues[inst].connected) return 0;

    const auto deadline = std::chrono::steady_clock::now() +
                          std::chrono::milliseconds(kRecvTimeoutMs);
    auto &queue = _queues[inst].replies;
    uint16_t received = 0;
    for (;;) {
        while (!queue.empty()) {
            Packet packet = std::move(queue.front());
            queue.pop_front();
            if (packet.sender == inst || isStale(packet.timestamp, timestamp)) continue;
            if (packet.aid == 0 || packet.aid > 15) continue;   // fuera del búfer
            // Hueco FIJO por AID: lo impone el core, que luego lee cada
            // respuesta en su sitio. Se recorta antes que desbordar al vecino.
            const size_t room = static_cast<size_t>(kReplyStride);
            const size_t len = std::min(packet.data.size(), room);
            std::memcpy(out + (packet.aid - 1) * kReplyStride, packet.data.data(), len);
            received |= static_cast<uint16_t>(1u << packet.aid);
            if ((received & aidmask) == aidmask) return received;   // ya están todos
        }
        if (_arrived.wait_until(lock, deadline) == std::cv_status::timeout) return received;
        if (!_queues[inst].connected) return received;
    }
}

#if DEBUG
void MPLoopback::selfCheck() {
    MPLoopback mp;
    mp.begin(0);
    mp.begin(1);

    // El host manda un CMD y el cliente lo ve como paquete de host.
    const uint8_t cmd[] = {0xDE, 0xAD, 0xBE, 0xEF};
    assert(mp.sendCmd(0, cmd, sizeof(cmd), 1000) == (int)sizeof(cmd));
    uint8_t buffer[kReplyStride * 16] = {};
    uint64_t ts = 0;
    assert(mp.recvHostPacket(1, buffer, &ts) == (int)sizeof(cmd));
    assert(ts == 1000 && buffer[0] == 0xDE && buffer[3] == 0xEF);

    // Quien lo envía no lo recibe.
    assert(mp.recvPacket(0, buffer, &ts) == 0);

    // La respuesta del cliente aterriza en su hueco, no en el principio.
    const uint8_t reply[] = {0x11, 0x22};
    assert(mp.sendReply(1, reply, sizeof(reply), 1000, 2) == (int)sizeof(reply));
    std::memset(buffer, 0, sizeof(buffer));
    const uint16_t got = mp.recvReplies(0, buffer, 1000, 1 << 2);
    assert(got == (1 << 2));
    assert(buffer[0] == 0 && buffer[kReplyStride] == 0x11 && buffer[kReplyStride + 1] == 0x22);

    // Un paquete viejo se descarta: es lo que evita arrastrar el frame anterior.
    mp.sendReply(1, reply, sizeof(reply), 1000, 2);
    assert(mp.recvReplies(0, buffer, 1000 + kStaleWindow + 1, 1 << 2) == 0);

    // Y con el reloj por debajo de la ventana no se da la vuelta el unsigned.
    mp.sendReply(1, reply, sizeof(reply), 0, 2);
    assert(mp.recvReplies(0, buffer, 1, 1 << 2) == (1 << 2));

    // Si el host se va, el cliente recibe -1 y no se queda esperando.
    mp.end(0);
    assert(mp.recvHostPacket(1, buffer, &ts) == -1);
    mp.end(1);
}

// Inicializador estático: corre al cargar el binario en Debug, sin que nadie
// tenga que acordarse de llamarlo. Verificado que aborta si un assert falla.
namespace { const bool gLoopbackSelfCheckRan = (MPLoopback::selfCheck(), true); }
#endif

}
