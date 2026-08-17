//
//  INDSMPLoopback.h
//  eNDS
//
//  Transporte de multijugador en proceso: varias instancias del core en la
//  misma app hablando entre ellas por colas de memoria. No toca la red.
//
//  Existe por dos motivos, y el segundo es el importante:
//
//   1. Es la referencia contra la que comparar el transporte de verdad. Si
//      dos partidas no se sincronizan aquí, donde la latencia es cero y no
//      hay pérdida de paquetes, no se van a sincronizar por Wi-Fi.
//   2. Aísla la máquina de estados del lockstep de la red. En iGBA los 16
//      bugs críticos del cable salieron de mezclar las dos cosas desde el
//      principio y no poder decir cuál de las dos fallaba.
//

#ifndef INDS_MP_LOOPBACK_H
#define INDS_MP_LOOPBACK_H

#include "INDSMPTransport.h"

#include <chrono>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <vector>

namespace eNDS {

class MPLoopback : public MPTransport {
public:
    static constexpr int kMaxInstances = 16;

    void begin(int inst) override;
    void end(int inst) override;

    int sendPacket(int inst, const uint8_t *data, int len, uint64_t timestamp) override;
    int recvPacket(int inst, uint8_t *out, uint64_t *timestamp) override;
    int sendCmd(int inst, const uint8_t *data, int len, uint64_t timestamp) override;
    int sendReply(int inst, const uint8_t *data, int len, uint64_t timestamp, uint16_t aid) override;
    int sendAck(int inst, const uint8_t *data, int len, uint64_t timestamp) override;
    int recvHostPacket(int inst, uint8_t *out, uint64_t *timestamp) override;
    uint16_t recvReplies(int inst, uint8_t *out, uint64_t timestamp, uint16_t aidmask) override;

#if DEBUG
    /// Comprobación con asserts del contrato de arriba. Se ejecuta sola al
    /// cargar en Debug: esto es una máquina de estados con relojes y máscaras
    /// de bits, y romperla en silencio es justo lo que no se puede permitir.
    static void selfCheck();
#endif

private:
    struct Packet {
        std::vector<uint8_t> data;
        uint64_t timestamp = 0;
        int sender = -1;
        uint16_t aid = 0;
        bool fromHost = false;
    };

    struct Queue {
        std::deque<Packet> packets;   // tráfico normal + CMD del host
        std::deque<Packet> replies;   // respuestas de los clientes
        bool connected = false;
    };

    /// Deja el paquete en la cola de todos menos en la del que lo envía.
    int broadcast(int from, const uint8_t *data, int len, uint64_t timestamp,
                  bool toReplyQueue, bool fromHost, uint16_t aid);
    /// Saca el primer paquete no caducado, esperando hasta `kRecvTimeoutMs`.
    int receive(int inst, uint8_t *out, uint64_t *timestamp, bool hostOnly);

    std::mutex _lock;
    std::condition_variable _arrived;
    Queue _queues[kMaxInstances];
    int _lastHostID = -1;
};

}

#endif // INDS_MP_LOOPBACK_H
