# Bluetooth Battery Monitor Tray 🔋🎧

> **Monitor de nível de bateria de dispositivos Bluetooth na Área de Notificação (System Tray) do Windows, desenvolvido em PowerShell nativo.**

Um utilitário leve, portátil e sem dependências externas pesadas, desenvolvido para fornecer visibilidade contínua e em tempo real da bateria de fones de ouvido, caixas de som, mouses e outros dispositivos Bluetooth diretamente na barra de tarefas do Windows.

---

## ✨ Principais Recursos

- 📊 **Exibição em Tempo Real na Bandeja:**
  - Acompanhe a porcentagem exata da bateria diretamente no ícone da Área de Notificação.
  - Código de cores dinâmico de fácil leitura:
    - 🟢 **Verde:** Bateria saudável (> 40%)
    - 🟡 **Âmbar:** Atenção (21% a 40%)
    - 🔴 **Vermelho:** Nível crítico (<= 20%)
    - ⚪ **Cinza:** Dispositivo desconectado (`--`)
- 🎨 **Alta Visibilidade & GDI+ Otimizado:**
  - Renderização vetorial com traço reforçado em alta resolução.
  - Fundo dinâmico adaptativo que acompanha automaticamente o tema da barra de tarefas (Modo Claro ou Escuro do Windows).
- 🔄 **Modos de Exibição Personalizáveis:**
  - **Apenas Porcentagem:** Exibe o número com o valor da bateria.
  - **Apenas Ícone do Dispositivo:** Exibe o glifo do aparelho estilizado com a cor da carga.
  - **Alternar a cada 1s:** Alterna suavemente entre o ícone do aparelho e o valor numérico em tempo real.
- 🎧 **Glifos Vetoriais Nativos:**
  - Reconhecimento automático ou seleção manual de ícones (`Segoe Fluent Icons` / `Segoe MDL2 Assets`):
    - Fones de ouvido / Headsets
    - Caixas de som / Alto-falantes
    - Mouses
    - Celulares / Smartphones
    - Microfones
- 🤹 **Suporte a Múltiplas Instâncias Simultâneas:**
  - Monitore múltiplos dispositivos simultaneamente (ex.: Fone de ouvido + Mouse + Caixa de som), cada um com seu próprio ícone independente na bandeja do sistema.
  - Prevenção automática de instâncias duplicadas para o mesmo dispositivo via Mutex exclusivo por endereço MAC.
- ⚡ **Detecção Fidedigna de Desconexão:**
  - Monitora o status real de conexão via propriedade PnP `DEVPKEY_Device_IsConnected`, descartando caches obsoletos do Windows no momento em que o aparelho é desligado.
- 🔔 **Alertas e Monitoramento Adaptativo:**
  - Notificação balão nativa do Windows avisando quando a bateria atingir nível crítico (<= 20%).
  - Ajuste dinâmico de intervalo: intensifica a checagem para 1 minuto em bateria baixa e retorna automaticamente ao padrão (2 minutos) ao ser recarregado.
- 🚀 **Autoinicialização com o Windows:**
  - Ative ou desative o início automático com um clique no menu de contexto.
  - Inicialização 100% silenciosa em segundo plano via pasta de Inicialização do usuário (`shell:startup`), sem telas pretas e sem necessidade de permissões de Administrador.

---

## 📋 Pré-requisitos

- **Sistema Operacional:** Windows 10 ou Windows 11 (64-bit ou 32-bit).
- **PowerShell:** Versão 5.1 ou superior (já pré-instalado em todas as versões modernas do Windows).
- **Hardware:** Adaptador Bluetooth ativo e dispositivo emparelhado compatível com relatório de bateria do Windows (HFP / GATT Battery Service).

---

## 🚀 Como Usar

### 1. Clonar ou Baixar o Repositório
```bash
git clone https://github.com/toth-trimes/Bluetooth-Battery-Monitor-Tray.git
```
Ou baixe o arquivo `.zip` pelo botão **Code > Download ZIP** e extraia em qualquer pasta de sua preferência.

### 2. Iniciar o Monitor
- Dê um duplo clique no arquivo **`Monitorar_Bateria_Bluetooth.bat`**.
- O menu interativo listará os dispositivos Bluetooth emparelhados, destacando em verde os que estão conectados no momento.
- Digite o número do dispositivo desejado ou pressione `ENTER` para selecionar o padrão.
- A janela do console será ocultada automaticamente e o ícone surgirá na bandeja do sistema (próximo ao relógio).

### 3. Interagir com o Menu da Bandeja
Clique com o **botão direito do mouse** sobre o ícone do monitor na bandeja para acessar:
- 🔄 **Forçar Atualização Agora**
- 🔁 **Trocar Dispositivo**
- ⏱️ **Intervalo de Atualização** (30s, 1m, 2m, 3m, 5m)
- 👁️ **Modo de Exibição** (Número, Ícone, Alternar)
- 🎧 **Ícone do Dispositivo** (Auto, Fone, Caixa, Mouse, Celular, Microfone)
- 📌 **Iniciar com o Windows** (Marcar/Desmarcar com [✔])
- ❌ **Sair**

---

## 📂 Estrutura de Arquivos

```text
Bluetooth-Battery-Monitor-Tray/
├── Monitorar_Bateria_Bluetooth.bat   # Lançador amigável com bypass de política de execução
├── monitor_bateria_bluetooth.ps1     # Motor principal em PowerShell com rotinas Win32 e GDI+
├── .gitignore                        # Desconsidera arquivos de preferências e atalhos locais
├── LICENSE                           # Licença MIT
└── README.md                         # Documentação do projeto
```

---

## 🔒 Privacidade e Segurança

- Este utilitário opera **100% offline** e em espaço de usuário (*user-space*).
- Não envia dados para a internet, não coleta telemetria e não modifica chaves sensíveis do sistema operacional.
- Os arquivos de configuração de preferências locais (`bt_config_*.json`) são armazenados apenas na pasta do script e já estão incluídos no `.gitignore`.

---

## 📄 Licença

Distribuído sob a licença **MIT**. Consulte o arquivo [`LICENSE`](LICENSE) para mais detalhes.
