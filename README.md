# Taller 2 — Apache Kafka con Podman y WSL2

Este repositorio contiene el material del **Taller 2** de capacitación práctica, enfocado en **Consumer Groups, Rebalanceo y Retención** en un clúster de Kafka con **3 brokers + Zookeeper**, ejecutado en **WSL2 (Ubuntu 24.04) con Podman**.

## 📂 Contenido

Los materiales principales están en la carpeta `docs/`:

- [`index_taller2_simple.html`](docs/index_taller2_simple.html) → **Índice principal** con accesos rápidos.
- [`taller2_topic1_retencion_v2.html`](docs/taller2_topic1_retencion_v2.html) → Tópico 1: Retención inicial.
- [`taller2_topic2_consumergroups.html`](docs/taller2_topic2_consumergroups.html) → Tópico 2: Consumer Groups.
- [`taller2_topic3_rebalanceo.html`](docs/taller2_topic3_rebalanceo.html) → Tópico 3: Rebalanceo.
- [`taller2_topic4_retencion.html`](docs/taller2_topic4_retencion.html) → Tópico 4: Retención avanzada.

## 🚀 Cómo usarlo

1. Asegúrate de tener levantado el clúster del Taller 1:

   ```bash
   podman ps
   ```
   Debes ver 4 contenedores activos: `zookeeper`, `kafka1`, `kafka2`, `kafka3`.

2. Abre el índice principal en tu navegador:

   - Localmente: abre `docs/index_taller2_simple.html`.
   - En GitHub Pages (si está publicado):  
     👉 `https://<usuario>.github.io/<repo>/docs/index_taller2_simple.html`

3. Sigue los pasos de cada Tópico:
   - **Tópico 1:** Crear un tópico y validar retención.  
   - **Tópico 2:** Ejecutar consumidores en grupo.  
   - **Tópico 3:** Probar rebalanceo al cerrar/abrir consumidores.  
   - **Tópico 4:** Configurar políticas de retención avanzadas.

## 📌 Requisitos

- WSL2 (Ubuntu 24.04)  
- Podman 4.9+  
- Podman Compose  
- Git configurado  

## 👩‍💻 Autora

Preparado por **Alejandra Montaña** · 2025  
Curso práctico en sistemas distribuidos con Kafka.
