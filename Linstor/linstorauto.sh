#!/bin/bash

clear

# Barvy pro výstup
COLOR_BLUE='\033[0;34m'
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[0;33m'
COLOR_NC='\033[0m' # No Color

# Funkce pro zobrazení zprávy s barvou a dotazem
function display_and_confirm {
    local message="$1"
    local color="$2"
    echo -e "${color}### ${message} ###${COLOR_NC}"
    read -p "$(echo -e "${COLOR_YELLOW}Chceš pokračovat? (ano/ne): ${COLOR_NC}")" choice
    if [[ "$choice" != "ano" ]]; then
        echo -e "${COLOR_RED}Instalace přerušena uživatelem.${COLOR_NC}"
        exit 1
    fi
}

# Funkce pro zobrazení checkpointu
function checkpoint {
    local message="$1"
    echo -e "\n${COLOR_GREEN}✓ CHECKPOINT: ${message}${COLOR_NC}\n"
}

# Funkce pro spuštění příkazu a kontrolu chyby (tichý výstup)
function run_command_quiet {
    local command="$1"
    local success_message="$2"
    local error_message="$3"
    echo -e "${COLOR_BLUE}Spouštím: ${command}${COLOR_NC}"
    if eval "$command" &> /dev/null; then
        echo -e "${COLOR_GREEN}${success_message}${COLOR_NC}"
        return 0
    else
        echo -e "${COLOR_RED}${error_message}${COLOR_NC}"
        return 1
    fi
}

# Funkce pro spuštění příkazu a kontrolu chyby (viditelný výstup)
function run_command_verbose {
    local command="$1"
    local success_message="$2"
    local error_message="$3"
    echo -e "${COLOR_BLUE}Spouštím: ${command}${COLOR_NC}"
    if eval "$command"; then
        echo -e "${COLOR_GREEN}${success_message}${COLOR_NC}"
        return 0
    else
        echo -e "${COLOR_RED}${error_message}${COLOR_NC}"
        return 1
    fi
}

# Funkce pro ruční zadávání uzlů
function manual_node_input {
    local node_count=0
    NODES=()
    NODE_IPS=()
    echo -e "${COLOR_YELLOW}Přepínám na ruční zadávání uzlů.${COLOR_NC}"
    while true; do
        node_count=$((node_count + 1))
        read -p "$(echo -e "${COLOR_YELLOW}Zadej hostname uzlu ${node_count} (nebo 'NO-MORE' pro ukončení přidávání uzlů): ${COLOR_NC}")" node_name
        if [[ "$node_name" == "NO-MORE" || "$node_name" == "no-more" ]]; then
            break
        fi
        read -p "$(echo -e "${COLOR_YELLOW}Zadej IP adresu uzlu ${node_name}: ${COLOR_NC}")" node_ip

        NODES+=("$node_name")
        NODE_IPS+=("$node_ip")
    done
}

# Funkce pro přidání uzlů do /etc/hosts
function add_nodes_to_hosts {
    echo -e "${COLOR_BLUE}--- Krok: Aktualizace /etc/hosts na všech uzlech clusteru. ---${COLOR_NC}"

    # Získání doménového jména z hostname - to je odhad, zvažte ruční zadání nebo přesnější detekci
    local DOMAIN_NAME=$(hostname -f | sed 's/^[^.]*\.//')
    if [ -z "$DOMAIN_NAME" ] || [[ "$DOMAIN_NAME" == "$LOCAL_HOSTNAME" ]]; then
        read -p "$(echo -e "${COLOR_YELLOW}Nepodařilo se automaticky detekovat doménové jméno (např. 'yourdomain.local'). Zadej ho prosím ručně (nebo stiskni Enter, pokud nechceš FQDN přidávat): ${COLOR_NC}")" MANUAL_DOMAIN_NAME
        if [ -n "$MANUAL_DOMAIN_NAME" ]; then
            DOMAIN_NAME="$MANUAL_DOMAIN_NAME"
        else
            DOMAIN_NAME="" # Žádná doména, FQDN nebude přidáno
        fi
    fi

    local hosts_need_update=false # Proměnná pro sledování, zda je potřeba aktualizace

    # Vygenerujeme seznam ideálních záznamů pro cluster (IP hostname FQDN)
    declare -A IDEAL_HOST_ENTRIES # Asociativní pole pro snadnější kontrolu
    for j in "${!NODES[@]}"; do
        local check_node_ip="${NODE_IPS[$j]}"
        local check_node_name="${NODES[$j]}"
        local fqdn_entry="${check_node_name}"
        if [ -n "$DOMAIN_NAME" ]; then
            fqdn_entry="${check_node_name}.${DOMAIN_NAME}"
        fi
        IDEAL_HOST_ENTRIES["${check_node_ip} ${check_node_name} ${fqdn_entry}"]=1
    done

    # Nejprve zkontrolujeme, zda jsou všechny ideální záznamy přítomny na všech uzlech
    for i in "${!NODES[@]}"; do
        local current_node_name="${NODES[$i]}"
        local current_node_ip="${NODE_IPS[$i]}"
        
        echo -e "${COLOR_BLUE}Kontroluji /etc/hosts na uzlu ${current_node_name} (${current_node_ip})...${COLOR_NC}"
        
        local current_node_hosts=$(ssh "$current_node_ip" "cat /etc/hosts")
        local missing_on_this_node=false

        for ideal_entry_strict in "${!IDEAL_HOST_ENTRIES[@]}"; do
            # Rozdělíme ideální záznam na IP, hostname a FQDN pro flexibilní hledání
            local ideal_ip=$(echo "$ideal_entry_strict" | awk '{print $1}')
            local ideal_hostname=$(echo "$ideal_entry_strict" | awk '{print $2}')
            local ideal_fqdn=$(echo "$ideal_entry_strict" | awk '{print $3}')

            # Flexibilní regex pro kontrolu: IP a hostname/FQDN v jakémkoli pořadí
            # Hledáme řádek začínající ideální IP adresou
            # a na kterém se nachází ideální hostname A ideální FQDN, oddělené mezerami
            local grep_pattern_flexible="^${ideal_ip//./\\.}\b.*(\b${ideal_hostname}\b.*)?(\b${ideal_fqdn//./\\.}\b.*)?\$"
            
            # Další varianta pro jistotu:
            # Check for IP, then check if both hostname and FQDN are present on the same line, regardless of order
            local grep_pattern_both_names="^${ideal_ip//./\\.}\b.*${ideal_hostname}\b.*${ideal_fqdn//./\\.}\b\|^${ideal_ip//./\\.}\b.*${ideal_fqdn//./\\.}\b.*${ideal_hostname}\b"

            if ! echo "$current_node_hosts" | grep -qE "$grep_pattern_both_names"; then
                echo -e "${COLOR_RED}Záznam pro ${ideal_ip} (${ideal_hostname} a ${ideal_fqdn}) CHYBÍ nebo NENÍ PŘESNÝ v /etc/hosts na uzlu ${current_node_name}.${COLOR_NC}"
                missing_on_this_node=true
                hosts_need_update=true # Nastaví globální flag
            fi
        done
        
        if ! $missing_on_this_node; then
            echo -e "${COLOR_GREEN}Všechny potřebné záznamy jsou v /etc/hosts na uzlu ${current_node_name}.${COLOR_NC}"
        fi
    done

    if $hosts_need_update; then
        read -p "$(echo -e "${COLOR_YELLOW}Některé záznamy v /etc/hosts chybí nebo jsou neúplné/nesprávné na jednom či více uzlech. Chceš je PŘIDAT/AKTUALIZOVAT na všechny uzly? (ano/ne): ${COLOR_NC}")" choice_confirm_add
        if [[ "$choice_confirm_add" != "ano" ]]; then
            echo -e "${COLOR_RED}Přidávání záznamů do /etc/hosts přerušeno uživatelem.${COLOR_NC}"
            checkpoint "/etc/hosts nebyl aktualizován na všech uzlech."
            return 0
        fi

        for i in "${!NODES[@]}"; do
            local current_node_name="${NODES[$i]}"
            local current_node_ip="${NODE_IPS[$i]}"
            
            echo -e "${COLOR_BLUE}Aktualizuji /etc/hosts na uzlu ${current_node_name} (${current_node_ip})...${COLOR_NC}"
            
            local hosts_file_content=$(ssh "$current_node_ip" "cat /etc/hosts")
            local new_hosts_content=""

            # Množina IP adres našich clusterových uzlů pro snadnou kontrolu
            declare -A cluster_ips
            for j in "${!NODE_IPS[@]}"; do
                cluster_ips["${NODE_IPS[$j]}"]=1
            done

            # Projdeme každou řádku existujícího /etc/hosts
            while IFS= read -r line; do
                local is_cluster_node_entry=false
                # Zkusíme extrahovat IP adresu z řádku
                local line_ip=$(echo "$line" | awk '{print $1}')
                
                # Zkontrolujeme, zda se IP adresa řádku shoduje s některou z IP adres našich clusterových uzlů
                if [[ -n "$line_ip" && "${cluster_ips[$line_ip]}" == "1" ]]; then
                    is_cluster_node_entry=true
                fi
                
                # Pokud řádek NENÍ jeden z našich clusterových záznamů, ponecháme ho
                # (tímto odstraníme všechny duplicitní nebo zastaralé záznamy našeho clusteru)
                if ! $is_cluster_node_entry; then
                    new_hosts_content+="$line\n"
                fi
            done <<< "$hosts_file_content"

            # Nyní přidáme ideální, aktuální záznamy pro VŠECHNY uzly clusteru (bez duplikátů)
            for ideal_entry in "${!IDEAL_HOST_ENTRIES[@]}"; do
                new_hosts_content+="${ideal_entry}\n"
            done

            # Zápis nového obsahu do /etc/hosts
            run_command_quiet "ssh ${current_node_ip} 'echo -e \"${new_hosts_content}\" | sudo tee /etc/hosts > /dev/null'" \
                "Záznamy v /etc/hosts aktualizovány na uzlu ${current_node_name}." \
                "Chyba při aktualizaci /etc/hosts na uzlu ${current_node_name}. Zkontroluj ručně."
        done
    else
        echo -e "${COLOR_GREEN}Všechny záznamy v /etc/hosts jsou na všech uzlech v pořádku. Přeskakuji krok.${COLOR_NC}"
    fi
    checkpoint "/etc/hosts aktualizován na všech uzlech."
}

# Záhlaví skriptu
echo -e "${COLOR_BLUE}===========================================${COLOR_NC}"
echo -e "${COLOR_BLUE} Průvodce instalací Linstor DRBD na Proxmox VE${COLOR_NC}"
echo -e "${COLOR_BLUE}===========================================${COLOR_NC}"
echo -e "${COLOR_YELLOW}Tento skript automatizuje instalaci Linstor DRBD na váš Proxmox VE cluster.${COLOR_NC}"
echo -e "${COLOR_YELLOW}Ujistěte se, že spouštíte tento skript na jednom z vašich Proxmox uzlů.${COLOR_NC}"
echo -e "${COLOR_YELLOW}Během instalace budete dotázáni na názvy uzlů a IP adresy.${COLOR_NC}"
read -p "$(echo -e "${COLOR_YELLOW}Jsi si vědom důležitosti zálohy a rizika, které s automatizovanou instalací souvisí? (ano/ne): ${COLOR_NC}")" confirm_risks
if [[ "$confirm_risks" != "ano" ]]; then
    echo -e "${COLOR_RED}Instalace přerušena.${COLOR_NC}"
    exit 1
fi

###
## Detekce Proxmox uzlů v clusteru

echo -e "${COLOR_BLUE}Pokouším se automaticky detekovat uzly ve vašem Proxmox VE clusteru...${COLOR_NC}"

DETECTED_NODES_TEMP=() # Pro uložení hostname:IP dvojic

# Získání hostname a IP adresy lokálního uzlu
LOCAL_HOSTNAME=$(hostname)
LOCAL_IP=$(hostname -I | awk '{print $1}') # Získá první IP adresu

# Kontrola, zda je pvecm dostupný a funkční
if ! command -v pvecm &> /dev/null; then
    echo -e "${COLOR_RED}Příkaz 'pvecm' nebyl nalezen. Není to Proxmox VE uzel nebo chybí potřebné balíčky.${COLOR_NC}"
    manual_node_input
else
    # Kontrola stavu clusteru a získání NodeID a IP adres z pvecm status
    CLUSTER_STATUS_OUTPUT=$(pvecm status 2>&1)
    if ! echo "${CLUSTER_STATUS_OUTPUT}" | grep -q 'Quorate:.*Yes'; then
        echo -e "${COLOR_YELLOW}Proxmox cluster NENÍ v quorate stavu nebo 'pvecm status' neobsahuje očekávané informace. Přecházím na ruční zadávání uzlů.${COLOR_NC}"
        manual_node_input
    else
        echo -e "${COLOR_GREEN}Proxmox cluster je detekován a je v quorate stavu.${COLOR_NC}"

        declare -A NODEID_TO_IP
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*0x([0-9a-f]+)[[:space:]]+[0-9]+[[:space:]]+([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}) ]]; then
                # Tyto proměnné jsou OK, protože jsou v podshellu (while read)
                HEX_NODE_ID="${BASH_REMATCH[1]}"
                IP_ADDRESS="${BASH_REMATCH[2]}"
                DEC_NODE_ID=$((16#$HEX_NODE_ID))
                NODEID_TO_IP[$DEC_NODE_ID]="$IP_ADDRESS"
            fi
        done <<< "$CLUSTER_STATUS_OUTPUT"

        if [ ${#NODEID_TO_IP[@]} -eq 0 ]; then
            echo -e "${COLOR_YELLOW}Nepodařilo se získat IP adresy z 'pvecm status'. Přecházím na ruční zadávání uzlů.${COLOR_NC}"
            manual_node_input
        else
            # Získání informací o uzlech z clusteru (hostnamy)
            NODE_INFO_OUTPUT=$(pvecm nodes 2>/dev/null)
            declare -A NODEID_TO_HOSTNAME

            while IFS= read -r line; do
                if [[ "$line" =~ ^[[:space:]]*([0-9]+)[[:space:]]+[0-9]+[[:space:]]+([^[:space:]]+) ]]; then
                    # Tyto proměnné jsou OK, protože jsou v podshellu (while read)
                    DEC_NODE_ID="${BASH_REMATCH[1]}"
                    HOSTNAME_OR_IP="${BASH_REMATCH[2]}"
                    
                    current_hostname="" # Tato proměnná je již v podshellu
                    if [[ "$HOSTNAME_OR_IP" =~ ^([[:alnum:]\._-]+)[[:space:]]*\(local\)$ ]]; then
                        current_hostname="${BASH_REMATCH[1]}"
                    elif [[ "$HOSTNAME_OR_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                        current_hostname="$LOCAL_HOSTNAME"
                    else
                        current_hostname="$HOSTNAME_OR_IP"
                    fi
                    NODEID_TO_HOSTNAME[$DEC_NODE_ID]="$current_hostname"
                fi
            done <<< "$NODE_INFO_OUTPUT"

            if [ ${#NODEID_TO_HOSTNAME[@]} -eq 0 ]; then
                echo -e "${COLOR_YELLOW}Nepodařilo se získat hostnamy z 'pvecm nodes'. Přecházím na ruční zadávání uzlů.${COLOR_NC}"
                manual_node_input
            else
                # Spojení informací a vygenerování finálního seznamu uzlů
                for node_id in "${!NODEID_TO_HOSTNAME[@]}"; do
                    # Tyto proměnné NEJSOU lokalní, protože jsou v hlavní části skriptu
                    node_hostname="${NODEID_TO_HOSTNAME[$node_id]}"
                    node_ip_val="${NODEID_TO_IP[$node_id]}" # Změněno jméno, aby nedocházelo k záměně s IP_ADDRESS

                    if [[ -n "$node_hostname" && -n "$node_ip_val" ]]; then
                        DETECTED_NODES_TEMP+=("${node_hostname}:${node_ip_val}")
                    else
                        echo -e "${COLOR_YELLOW}Varování: Chybí informace (hostname nebo IP) pro NodeID ${node_id}. Uzel nebude automaticky přidán.${COLOR_NC}"
                    fi
                done

                if [ ${#DETECTED_NODES_TEMP[@]} -gt 0 ]; then
                    echo -e "${COLOR_BLUE}Byly detekovány následující uzly:${COLOR_NC}"
                    for entry in "${DETECTED_NODES_TEMP[@]}"; do
                        echo -e "${COLOR_BLUE}- ${entry}${COLOR_NC}"
                    done
                    read -p "$(echo -e "${COLOR_YELLOW}Jsou detekované uzly v pořádku a všechny potřebné uzly pro Linstor jsou na tomto seznamu? (ano/ne): ${COLOR_NC}")" detection_ok
                    if [[ "$detection_ok" == "ano" ]]; then
                        # Převedení pole hostname:IP na samostatná pole NODES a NODE_IPS
                        NODES=()
                        NODE_IPS=()
                        for entry in "${DETECTED_NODES_TEMP[@]}"; do
                            IFS=':' read -r node_name node_ip <<< "$entry"
                            NODES+=("$node_name")
                            NODE_IPS+=("$node_ip")
                        done
                    else
                        echo -e "${COLOR_YELLOW}Detekce nebyla v pořádku, přecházím na ruční zadávání.${COLOR_NC}"
                        manual_node_input
                    fi
                else
                    echo -e "${COLOR_YELLOW}Automatická detekce nezjistila žádné uzly s přiřazenými IP adresami. Přecházím na ruční zadávání.${COLOR_NC}"
                    manual_node_input
                fi
            fi
        fi
    fi
fi

if [ ${#NODES[@]} -lt 2 ]; then
    echo -e "${COLOR_RED}Pro Linstor DRBD HA potřebujete alespoň 2 uzly. Instalace přerušena.${COLOR_NC}"
    exit 1
fi

echo -e "${COLOR_BLUE}Byly vybrány následující uzly pro instalaci:${COLOR_NC}"
for i in "${!NODES[@]}"; do
    echo -e "${COLOR_BLUE}- Uzel: ${NODES[$i]}, IP: ${NODE_IPS[$i]}${COLOR_NC}"
done
display_and_confirm "Potvrďte finální seznam uzlů pro instalaci." "$COLOR_YELLOW"

# Zde zavolejte novou funkci pro přidání uzlů do /etc/hosts
add_nodes_to_hosts

# Primární uzel je uzel, na kterém spouštíme skript.
# Zajistíme, že lokální uzel je první v seznamu.
PRIMARY_NODE=$LOCAL_HOSTNAME
PRIMARY_NODE_IP=$LOCAL_IP

local_node_found=false
for i in "${!NODES[@]}"; do
    if [[ "${NODES[$i]}" == "$PRIMARY_NODE" ]]; then
        if [[ "$i" -ne 0 ]]; then # Pokud není už na první pozici, prohodíme ho
            # Tyto proměnné NEJSOU lokalní, protože jsou v hlavní části skriptu
            temp_node="${NODES[0]}"
            temp_ip="${NODE_IPS[0]}"
            NODES[0]="$PRIMARY_NODE"
            NODE_IPS[0]="$PRIMARY_NODE_IP"
            NODES[$i]="$temp_node"
            NODE_IPS[$i]="$temp_ip"
        fi
        local_node_found=true
        break
    fi
done

if ! $local_node_found; then
    echo -e "${COLOR_RED}Chyba: Lokální uzel (${PRIMARY_NODE}) nebyl nalezen mezi detekovanými uzly. Zkontrolujte prosím konfiguraci Proxmox clusteru nebo ručně zadejte uzly.${COLOR_NC}"
    exit 1
fi

echo -e "${COLOR_BLUE}Primární uzel pro Linstor operace bude: ${PRIMARY_NODE} (${PRIMARY_NODE_IP})${COLOR_NC}"

###
## 1. Aktualizace Proxmoxu a instalace pve-headers

echo -e "${COLOR_BLUE}--- Krok 1: Aktualizace Proxmoxu a instalace pve-headers na všech uzlech. Toto je NUTNÉ pro funkčnost DRBD dkms. ---${COLOR_NC}"

ALL_HEADERS_INSTALLED=true
for i in "${!NODES[@]}"; do
    node_name="${NODES[$i]}"
    node_ip="${NODE_IPS[$i]}"
    echo -e "${COLOR_BLUE}Kontroluji pve-headers na uzlu ${node_name} (${node_ip})...${COLOR_NC}"
    # Zjednodušená a spolehlivější detekce pve-headers
    if ! ssh "$node_ip" "dpkg -l | grep -q \"^ii.*pve-headers\""; then
        echo -e "${COLOR_RED}pve-headers NEJSOU nainstalovány na uzlu ${node_name}.${COLOR_NC}"
        ALL_HEADERS_INSTALLED=false
    else
        echo -e "${COLOR_GREEN}pve-headers jsou nainstalovány na uzlu ${node_name}.${COLOR_NC}"
    fi
done

if ! $ALL_HEADERS_INSTALLED; then
    read -p "$(echo -e "${COLOR_YELLOW}Některé pve-headers chybí nebo nesouhlasí verze. Chceš je nainstalovat a aktualizovat Proxmox na všech uzlech? (ano/ne): ${COLOR_NC}")" choice
    if [[ "$choice" != "ano" ]]; then
        echo -e "${COLOR_RED}Instalace pve-headers přerušena uživatelem.${COLOR_NC}"
        exit 1
    fi

    for i in "${!NODES[@]}"; do
        # Tyto proměnné NEJSOU lokalní, protože jsou v hlavní části skriptu
        node_name="${NODES[$i]}"
        node_ip="${NODE_IPS[$i]}"
        echo -e "${COLOR_BLUE}Připojuji se k uzlu ${node_name} (${node_ip}) pro aktualizaci a instalaci pve-headers...${COLOR_NC}"
        run_command_quiet "ssh $node_ip 'apt update && apt dist-upgrade -y && apt install pve-headers -y'" \
            "Aktualizace a instalace pve-headers na uzlu ${node_name} proběhla úspěšně." \
            "Chyba při aktualizaci nebo instalaci pve-headers na uzlu ${node_name}. Zkontroluj ručně."
    done
else
    echo -e "${COLOR_GREEN}Všechny pve-headers jsou na všech uzlech v pořádku. Přeskakuji krok.${COLOR_NC}"
fi
checkpoint "Proxmox aktualizován a pve-headers nainstalovány na všech uzlech."

###
## 2. Přidání repositáře pro Linstor DRBD

echo -e "${COLOR_BLUE}### Krok 2: Přidání repositáře pro Linstor DRBD na všech uzlech. ###${COLOR_NC}"

ALL_REPOS_ADDED=true
for i in "${!NODES[@]}"; do
    node_name="${NODES[$i]}"
    node_ip="${NODE_IPS[$i]}"
    echo -e "${COLOR_BLUE}Kontroluji repositář Linstor na uzlu ${node_name} (${node_ip})...${COLOR_NC}"
    if ! ssh "$node_ip" "grep -q 'linbit.com' /etc/apt/sources.list.d/linbit.list &> /dev/null"; then
        echo -e "${COLOR_RED}Repositář Linstor NENÍ přidán na uzlu ${node_name}.${COLOR_NC}"
        ALL_REPOS_ADDED=false
    else
        echo -e "${COLOR_GREEN}Repositář Linstor je již přidán na uzlu ${node_name}.${COLOR_NC}"
    fi
done

if ! $ALL_REPOS_ADDED; then
    read -p "$(echo -e "${COLOR_YELLOW}Některé repositáře Linstor chybí. Chceš je přidat na všechny uzly? (ano/ne): ${COLOR_NC}")" choice
    if [[ "$choice" != "ano" ]]; then
        echo -e "${COLOR_RED}Přidávání repositářů Linstor přerušeno uživatelem.${COLOR_NC}"
        exit 1
    fi

    for i in "${!NODES[@]}"; do
        node_name="${NODES[$i]}"
        node_ip="${NODE_IPS[$i]}"
        echo -e "${COLOR_BLUE}Přidávám repositář Linstor na uzel ${node_name} (${node_ip})...${COLOR_NC}"
        run_command_quiet "ssh $node_ip 'wget -O /tmp/linbit-keyring.deb https://packages.linbit.com/public/linbit-keyring.deb && dpkg -i /tmp/linbit-keyring.deb && PVERS=\$(pveversion | grep -oP \"pve-manager/\K[0-9.]+\") && echo \"deb [signed-by=/etc/apt/trusted.gpg.d/linbit-keyring.gpg] http://packages.linbit.com/public/ proxmox-\$PVERS drbd-9\" > /etc/apt/sources.list.d/linbit.list && apt update'" \
            "Repositář Linstor přidán na uzel ${node_name} úspěšně." \
            "Chyba při přidávání repositáře Linstor na uzel ${node_name}. Zkontroluj ručně."
    done
else
    echo -e "${COLOR_GREEN}Všechny repositáře Linstor DRBD jsou přidány na všech uzlech. Přeskakuji krok.${COLOR_NC}"
fi
checkpoint "Repositář Linstor DRBD přidán na všechny uzly."

###
## 3. Instalace DRBD, drbdutils, linstor a pluginu linstor pro Proxmox

echo -e "${COLOR_BLUE}### Krok 3: Instalace DRBD, drbdutils, linstor a pluginu linstor pro Proxmox na všech uzlech. ###${COLOR_NC}"

ALL_LINSTOR_PACKAGES_INSTALLED=true
for i in "${!NODES[@]}"; do
    node_name="${NODES[$i]}"
    node_ip="${NODE_IPS[$i]}"
    echo -e "${COLOR_BLUE}Kontroluji instalaci Linstor balíčků na uzlu ${node_name} (${node_ip})...${COLOR_NC}"
    if ! ssh "$node_ip" "dpkg -s linstor-controller linstor-satellite drbd-dkms &> /dev/null"; then
        echo -e "${COLOR_RED}Linstor balíčky NEJSOU nainstalovány na uzlu ${node_name}.${COLOR_NC}"
        ALL_LINSTOR_PACKAGES_INSTALLED=false
    else
        echo -e "${COLOR_GREEN}Linstor balíčky jsou nainstalovány na uzlu ${node_name}.${COLOR_NC}"
    fi
done

if ! $ALL_LINSTOR_PACKAGES_INSTALLED; then
    read -p "$(echo -e "${COLOR_YELLOW}Některé Linstor balíčky chybí. Chceš je nainstalovat na všechny uzly? (ano/ne): ${COLOR_NC}")" choice
    if [[ "$choice" != "ano" ]]; then
        echo -e "${COLOR_RED}Instalace Linstor balíčků přerušena uživatelem.${COLOR_NC}"
        exit 1
    fi

    for i in "${!NODES[@]}"; do
        node_name="${NODES[$i]}"
        node_ip="${NODE_IPS[$i]}"
        echo -e "${COLOR_BLUE}Instaluji Linstor balíčky na uzel ${node_name} (${node_ip})...${COLOR_NC}"
        run_command_quiet "ssh $node_ip 'apt -y install drbd-dkms drbd-utils linstor-proxmox linstor-client linstor-controller linstor-satellite'" \
            "Linstor balíčky nainstalovány na uzel ${node_name} úspěšně." \
            "Chyba při instalaci Linstor balíčků na uzel ${node_name}. Zkontroluj ručně."
    done
else
    echo -e "${COLOR_GREEN}Linstor a DRBD balíčky jsou již nainstalovány na všech uzlech. Přeskakuji krok.${COLOR_NC}"
fi
checkpoint "Linstor a DRBD balíčky nainstalovány na všechny uzly."

###
## 4. Linstor controller úprava pro HighAvailability setup

echo -e "${COLOR_BLUE}### Krok 4: Zakázání Linstor controller daemonu na všech uzlech a ruční spuštění na primárním uzlu. ###${COLOR_NC}"

CONTROLLERS_DISABLED=true
for i in "${!NODES[@]}"; do
    node_name="${NODES[$i]}"
    node_ip="${NODE_IPS[$i]}"
    echo -e "${COLOR_BLUE}Kontroluji stav linstor-controller na uzlu ${node_name} (${node_ip})...${COLOR_NC}"
    if [[ "$node_name" != "$PRIMARY_NODE" ]]; then # Na ostatních uzlech musí být zakázán
        if ssh "$node_ip" "systemctl is-enabled linstor-controller &> /dev/null" || ssh "$node_ip" "systemctl is-active linstor-controller &> /dev/null"; then
            echo -e "${COLOR_RED}Linstor-controller JE povolen nebo aktivní na uzlu ${node_name} (měl by být zakázán).${COLOR_NC}"
            CONTROLLERS_DISABLED=false
        else
            echo -e "${COLOR_GREEN}Linstor-controller je zakázán a neaktivní na uzlu ${node_name}.${COLOR_NC}"
        fi
    else # Na primárním uzlu musí být aktivní a spuštěný ručně
        if ! ssh "$node_ip" "systemctl is-active linstor-controller &> /dev/null"; then
            echo -e "${COLOR_RED}Linstor-controller NENÍ aktivní na primárním uzlu ${node_name}.${COLOR_NC}"
            CONTROLLERS_DISABLED=false # Používám stejnou proměnnou, i když je to trochu jiná kontrola
        else
            echo -e "${COLOR_GREEN}Linstor-controller je aktivní na primárním uzlu ${node_name}.${COLOR_NC}"
        fi
    fi
done

if ! $CONTROLLERS_DISABLED; then
    read -p "$(echo -e "${COLOR_YELLOW}Linstor-controller není ve správném stavu na všech uzlech. Chceš provést úpravy a spustit na primárním? (ano/ne): ${COLOR_NC}")" choice
    if [[ "$choice" != "ano" ]]; then
        echo -e "${COLOR_RED}Úpravy linstor-controller přerušeny uživatelem.${COLOR_NC}"
        exit 1
    fi

    for i in "${!NODES[@]}"; do
        node_name="${NODES[$i]}"
        node_ip="${NODE_IPS[$i]}"
        if [[ "$node_name" != "$PRIMARY_NODE" ]]; then
            echo -e "${COLOR_BLUE}Zakazuji linstor-controller na uzlu ${node_name} (${node_ip})...${COLOR_NC}"
            run_command_quiet "ssh $node_ip 'systemctl disable linstor-controller --now'" \
                "Linstor-controller zakázán na uzlu ${node_name}." \
                "Chyba při zakazování linstor-controller na uzlu ${node_name}. Zkontroluj ručně."
        fi
    done

    echo -e "${COLOR_BLUE}Startuji linstor-controller ručně na primárním uzlu ${PRIMARY_NODE} (${PRIMARY_NODE_IP})...${COLOR_NC}"
    run_command_quiet "ssh $PRIMARY_NODE_IP 'systemctl start linstor-controller'" \
        "Linstor-controller nastartován na primárním uzlu." \
        "Chyba při startu linstor-controller na primárním uzlu. Zkontroluj ručně."
else
    echo -e "${COLOR_GREEN}Linstor controller je již připraven pro HA setup na všech uzlech. Přeskakuji krok.${COLOR_NC}"
fi
checkpoint "Linstor controller připraven pro HA setup."

###
## 5. Přidání nodů do Linstor clusteru

echo -e "${COLOR_BLUE}### Krok 5: Přidání nodů do Linstor clusteru. ###${COLOR_NC}"

echo -e "${COLOR_BLUE}Kontroluji stav Linstor nodů...${COLOR_NC}"
run_command_verbose "ssh $PRIMARY_NODE_IP 'linstor node list'" \
    "Kontrola Linstor nodů proběhla." \
    "Chyba při kontrole Linstor nodů."

NODES_TO_ADD=()
for i in "${!NODES[@]}"; do
    node_name="${NODES[$i]}"
    node_ip="${NODE_IPS[$i]}"
    echo -e "${COLOR_BLUE}Kontroluji, zda uzel ${node_name} je v Linstor clusteru...${COLOR_NC}"
    # Změněno: Odstraněno --output-version=1 a použito grep na hostname
    if ! ssh "$PRIMARY_NODE_IP" "linstor node list | grep -q \"^|\\s*${node_name}\\s*|\""; then
        echo -e "${COLOR_RED}Uzel ${node_name} NENÍ přidán do Linstor clusteru.${COLOR_NC}"
        NODES_TO_ADD+=("$node_name:$node_ip")
    else
        echo -e "${COLOR_GREEN}Uzel ${node_name} je již přidán do Linstor clusteru.${COLOR_NC}"
    fi
done

if [ ${#NODES_TO_ADD[@]} -gt 0 ]; then
    echo -e "${COLOR_YELLOW}Následující uzly nejsou v Linstor clusteru a budou přidány:${COLOR_NC}"
    for entry in "${NODES_TO_ADD[@]}"; do
        echo -e "${COLOR_YELLOW}- ${entry}${COLOR_NC}"
    done
    read -p "$(echo -e "${COLOR_YELLOW}Chceš pokračovat s přidáním chybějících uzlů do Linstor clusteru? (ano/ne): ${COLOR_NC}")" choice
    if [[ "$choice" != "ano" ]]; then
        echo -e "${COLOR_RED}Přidávání uzlů do Linstor clusteru přerušeno uživatelem.${COLOR_NC}"
        exit 1
    fi

    for entry in "${NODES_TO_ADD[@]}"; do
        IFS=':' read -r node_name node_ip <<< "$entry"
        echo -e "${COLOR_BLUE}Přidávám uzel ${node_name} (${node_ip}) do Linstor clusteru...${COLOR_NC}"
        run_command_quiet "ssh $PRIMARY_NODE_IP 'linstor node create $node_name $node_ip'" \
            "Uzel ${node_name} přidán do Linstor clusteru." \
            "Chyba při přidávání uzlu ${node_name} do Linstor clusteru. Zkontroluj ručně."
    done
else
    echo -e "${COLOR_GREEN}Všechny potřebné uzly jsou již v Linstor clusteru. Přeskakuji krok.${COLOR_NC}"
fi

echo -e "${COLOR_BLUE}Kontroluji stav Linstor nodů po operaci...${COLOR_NC}"
run_command_verbose "ssh $PRIMARY_NODE_IP 'linstor node list'" \
    "Všechny Linstor nody jsou online." \
    "Některé Linstor nody nejsou online. Zkontroluj ručně."
checkpoint "Všechny uzly přidány do Linstor clusteru a jsou online."

###
## 6. Příprava StoragePool pro Linstor databázi pro HA režim

echo -e "${COLOR_BLUE}### Krok 6: Vytvoření ZFS datasetu 'linstor_db' a Linstor StoragePoolu pro databázi na všech uzlech. ###${COLOR_NC}"

ALL_DB_STORAGE_READY=true
declare -A ZFS_POOL_NAMES # Asociativní pole pro ukládání názvů ZFS poolů pro každý uzel

# První průchod pro zjištění stavu a dotaz na ZFS pool
for i in "${!NODES[@]}"; do
    node_name="${NODES[$i]}"
    node_ip="${NODE_IPS[$i]}"
    
    # Dotaz na ZFS pool a jeho uložení
    read -p "$(echo -e "${COLOR_YELLOW}Zadej název ZFS poolu pro linstor_db na uzlu ${node_name} (např. 'fast' nebo 'tank'): ${COLOR_NC}")" zfs_pool_name
    ZFS_POOL_NAMES["$node_name"]="$zfs_pool_name" # Uložení pro pozdější použití

    # --- Kontrola ZFS datasetu ---
    echo -e "${COLOR_BLUE}Kontroluji ZFS dataset ${zfs_pool_name}/linstor_db na uzlu ${node_name} (${node_ip})...${COLOR_NC}"
    if ! ssh "$node_ip" "zfs list ${zfs_pool_name}/linstor_db &> /dev/null"; then
        echo -e "${COLOR_RED}ZFS dataset ${zfs_pool_name}/linstor_db NENÍ vytvořen na uzlu ${node_name}.${COLOR_NC}"
        ALL_DB_STORAGE_READY=false
    else
        echo -e "${COLOR_GREEN}ZFS dataset ${zfs_pool_name}/linstor_db JE vytvořen na uzlu ${node_name}.${COLOR_NC}"
    fi

    # --- Kontrola Linstor StoragePoolu ---
    echo -e "${COLOR_BLUE}Kontroluji Linstor StoragePool 'linstor_db' na uzlu ${node_name} (${node_ip})...${COLOR_NC}"
    # NEJROBUSTNĚJŠÍ DETEKCE: Hledáme všechna klíčová slova na jednom řádku, oddělená čímkoli.
    # To zabrání problémům s proměnlivým formátováním.
    if ! ssh "$PRIMARY_NODE_IP" "linstor sp list | grep -qE \"linstor_db.*${node_name}.*ZFS.*Ok\""; then
        echo -e "${COLOR_RED}Linstor StoragePool 'linstor_db' NENÍ vytvořen na uzlu ${node_name}.${COLOR_NC}"
        ALL_DB_STORAGE_READY=false
    else
        echo -e "${COLOR_GREEN}Linstor StoragePool 'linstor_db' JE vytvořen na uzlu ${node_name}.${COLOR_NC}"
    fi
done

if ! $ALL_DB_STORAGE_READY; then
    read -p "$(echo -e "${COLOR_YELLOW}Některé ZFS datasety nebo Linstor StoragePooly pro linstor_db chybí. Chceš je vytvořit? (ano/ne): ${COLOR_NC}")" choice
    if [[ "$choice" != "ano" ]]; then
        echo -e "${COLOR_RED}Vytváření StoragePoolu pro Linstor DB přerušeno uživatelem.${COLOR_NC}"
        exit 1
    fi

    for i in "${!NODES[@]}"; do
        node_name="${NODES[$i]}"
        node_ip="${NODE_IPS[$i]}"
        zfs_pool_name="${ZFS_POOL_NAMES["$node_name"]}" # Načtení názvu ZFS poolu
        linstor_sp_name="linstor_db" # Název StoragePoolu pro databázi

        echo -e "${COLOR_BLUE}Vytvářím ZFS dataset ${zfs_pool_name}/linstor_db na uzlu ${node_name} (${node_ip})...${COLOR_NC}"
        if ! ssh "$node_ip" "zfs list ${zfs_pool_name}/linstor_db &> /dev/null"; then
            run_command_quiet "ssh $node_ip 'zfs create ${zfs_pool_name}/linstor_db'" \
                "ZFS dataset ${zfs_pool_name}/linstor_db vytvořen na uzlu ${node_name}." \
                "Chyba při vytváření ZFS datasetu na uzlu ${node_name}. Zkontroluj ručně."
        else
            echo -e "${COLOR_GREEN}ZFS dataset ${zfs_pool_name}/linstor_db již existuje na uzlu ${node_name}. Přeskakuji.${COLOR_NC}"
        fi

        echo -e "${COLOR_BLUE}Vytvářím Linstor StoragePool '${linstor_sp_name}' na uzlu ${node_name} (${node_ip})...${COLOR_NC}"
        # Použita stejná robustní detekce před pokusem o vytvoření
        if ! ssh "$PRIMARY_NODE_IP" "linstor sp list | grep -qE \"${linstor_sp_name}.*${node_name}.*ZFS.*Ok\""; then
            run_command_quiet "ssh $PRIMARY_NODE_IP 'linstor storage-pool create zfs $node_name ${linstor_sp_name} ${zfs_pool_name}/linstor_db'" \
                "Linstor StoragePool '${linstor_sp_name}' vytvořen na uzlu ${node_name}." \
                "Chyba při vytváření Linstor StoragePoolu na uzlu ${node_name}. Zkontroluj ručně."
        else
            echo -e "${COLOR_GREEN}Linstor StoragePool '${linstor_sp_name}' již existuje na uzlu ${node_name}. Přeskakuji.${COLOR_NC}"
        fi
    done
else
    echo -e "${COLOR_GREEN}Všechny ZFS datasety a Linstor StoragePooly pro linstor_db jsou vytvořeny. Přeskakuji krok.${COLOR_NC}"
fi

echo -e "${COLOR_BLUE}Kontroluji Linstor StoragePooly...${COLOR_NC}"
run_command_verbose "ssh $PRIMARY_NODE_IP 'linstor sp l'" \
    "Linstor StoragePooly jsou nastaveny." \
    "Chyba při kontrole Linstor StoragePoolů. Zkontroluj ručně."
checkpoint "StoragePool 'linstor_db' vytvořen a zkontrolován na všech uzlech."

###
## 7. Kontrola podpory DRBD vrstvy

echo -e "${COLOR_BLUE}### Krok 7: Kontrola podpory DRBD vrstvy na všech uzlech. ###${COLOR_NC}"

echo -e "${COLOR_BLUE}Kontroluji podporu DRBD vrstvy na všech uzlech...${COLOR_NC}"
# Tato kontrola pouze vypíše stav, není potřeba potvrzovat, protože nic nemění.
run_command_verbose "ssh $PRIMARY_NODE_IP 'linstor node info'" \
    "Kontrola podpory DRBD vrstvy proběhla úspěšně." \
    "Chyba při kontrole podpory DRBD vrstvy. Zkontroluj ručně. Pokud je u DRBD mínus, je to chyba!"
checkpoint "Podpora DRBD vrstvy zkontrolována."

###
## 8. Vytvoření resource pro Linstor databázi

echo -e "${COLOR_BLUE}### Krok 8: Vytvoření resource pro Linstor databázi s HA režimem. ###${COLOR_NC}"

RESOURCE_DB_READY=true
echo -e "${COLOR_BLUE}Kontroluji Resource-Group 'linstor_rg'...${COLOR_NC}"
# Změněno: Odstraněno --output-version=1 a použito grep na název RG
if ! ssh "$PRIMARY_NODE_IP" "linstor rg list | grep -q \"^|\\s*linstor_rg\\s*|\""; then
    echo -e "${COLOR_RED}Resource-group 'linstor_rg' NENÍ vytvořena.${COLOR_NC}"
    RESOURCE_DB_READY=false
else
    echo -e "${COLOR_GREEN}Resource-group 'linstor_rg' JE vytvořena.${COLOR_NC}"
fi

echo -e "${COLOR_BLUE}Kontroluji Resource 'linstor_db'...${COLOR_NC}"
# Změněno: Odstraněno --output-version=1 a použito grep na název resource definition
if ! ssh "$PRIMARY_NODE_IP" "linstor rd list | grep -q \"^|\\s*linstor_db\\s*|\""; then
    echo -e "${COLOR_RED}Resource 'linstor_db' NENÍ vytvořen.${COLOR_NC}"
    RESOURCE_DB_READY=false
else
    echo -e "${COLOR_GREEN}Resource 'linstor_db' JE vytvořen.${COLOR_NC}"
fi

if ! $RESOURCE_DB_READY; then
    read -p "$(echo -e "${COLOR_YELLOW}Resource-group 'linstor_rg' nebo Resource 'linstor_db' chybí. Chceš je vytvořit a nastavit parametry? (ano/ne): ${COLOR_NC}")" choice
    if [[ "$choice" != "ano" ]]; then
        echo -e "${COLOR_RED}Vytváření resource pro Linstor DB přerušeno uživatelem.${COLOR_NC}"
        exit 1
    fi

    echo -e "${COLOR_BLUE}Vytvářím resource-group 'linstor_rg' a resource 'linstor_db'...${COLOR_NC}"
    # Změněno: Odstraněno --output-version=1
    if ! ssh "$PRIMARY_NODE_IP" "linstor rg list | grep -q \"^|\\s*linstor_rg\\s*|\""; then
        run_command_quiet "ssh $PRIMARY_NODE_IP 'linstor resource-group create linstor_rg --storage-pool linstor_db --place-count ${#NODES[@]}'" \
            "Resource-group 'linstor_rg' vytvořena." \
            "Chyba při vytváření resource-group 'linstor_rg'. Zkontroluj ručně."
    else
        echo -e "${COLOR_GREEN}Resource-group 'linstor_rg' již existuje. Přeskakuji vytváření.${COLOR_NC}"
    fi

    # Změněno: Odstraněno --output-version=1
    if ! ssh "$PRIMARY_NODE_IP" "linstor rd list | grep -q \"^|\\s*linstor_db\\s*|\""; then
        run_command_quiet "ssh $PRIMARY_NODE_IP 'linstor resource-group sp linstor_rg StorDriver/ZfscreateOptions \"-b 32k\"'" \
            "Velikost bloků nastavena pro 'linstor_rg'." \
            "Chyba při nastavování velikosti bloků. Zkontroluj ručně."

        run_command_quiet "ssh $PRIMARY_NODE_IP 'linstor resource-group spawn-resources linstor_rg linstor_db 200M'" \
            "Resource 'linstor_db' vytvořen." \
            "Chyba při vytváření resource 'linstor_db'. Zkontroluj ručně."

        echo -e "${COLOR_BLUE}Nastavuji doporučené parametry pro resource 'linstor_db'...${COLOR_NC}"
        run_command_quiet "ssh $PRIMARY_NODE_IP 'linstor rd drbd-options --auto-promote=no linstor_db'" "Parametr --auto-promote nastaven." "Chyba při nastavení parametru."
        run_command_quiet "ssh $PRIMARY_NODE_IP 'linstor rd drbd-options --quorum=majority linstor_db'" "Parametr --quorum nastaven." "Chyba při nastavení parametru."
        run_command_quiet "ssh $PRIMARY_NODE_IP 'linstor rd drbd-options --on-suspended-primary-outdated=force-secondary linstor_db'" "Parametr --on-suspended-primary-outdated nastaven." "Chyba při nastavení parametru."
        run_command_quiet "ssh $PRIMARY_NODE_IP 'linstor rd drbd-options --on-no-quorum=io-error linstor_db'" "Parametr --on-no-quorum nastaven." "Chyba při nastavení parametru."
        run_command_quiet "ssh $PRIMARY_NODE_IP 'linstor rd drbd-options --on-no-data-accessible=io-error linstor_db'" "Parametr --on-no-data-accessible nastaven." "Chyba při nastavení parametru."
        run_command_quiet "ssh $PRIMARY_NODE_IP 'linstor rd drbd-options --rr-conflict=retry-connect linstor_db'" "Parametr --rr-conflict nastaven." "Chyba při nastavení parametru."
    else
        echo -e "${COLOR_GREEN}Resource 'linstor_db' již existuje. Přeskakuji vytváření a nastavování.${COLOR_NC}"
    fi
else
    echo -e "${COLOR_GREEN}Resource 'linstor_db' a jeho parametry jsou nastaveny. Přeskakuji krok.${COLOR_NC}"
fi
checkpoint "Resource 'linstor_db' a jeho parametry nastaveny."

###
## 9. Kontrola funkčnosti replikace resource

echo -e "${COLOR_BLUE}### Krok 9: Kontrola funkčnosti replikace resource 'linstor_db'. ###${COLOR_NC}"

echo -e "${COLOR_BLUE}Kontroluji stav resource 'linstor_db'...${COLOR_NC}"
# Tato kontrola pouze vypíše stav, není potřeba potvrzovat, protože nic nemění.
run_command_verbose "ssh $PRIMARY_NODE_IP 'linstor r l'" \
    "Resource 'linstor_db' je replikován a funkční (mělo by být 'UpToDate')." \
    "Chyba při kontrole resource 'linstor_db' nebo stav není UpToDate. Zkontroluj ručně."
checkpoint "Replikace Linstor databáze je funkční."

###
## 10. Příprava služeb na nodech pro Linstor HA

echo -e "${COLOR_BLUE}### Krok 10: Příprava služeb pro Linstor HA na všech uzlech. ###${COLOR_NC}"

ALL_SERVICES_READY=true
for i in "${!NODES[@]}"; do
    node_name="${NODES[$i]}"
    node_ip="${NODE_IPS[$i]}"
    
    echo -e "${COLOR_BLUE}Kontroluji službu pro DRBD mount adresáře na uzlu ${node_name} (${node_ip})...${COLOR_NC}"
    if ! ssh "$node_ip" "test -f /etc/systemd/system/var-lib-linstor.mount && grep -q '/dev/drbd/by-res/linstor_db/0' /etc/systemd/system/var-lib-linstor.mount"; then
        echo -e "${COLOR_RED}Soubor var-lib-linstor.mount NENÍ správně nastaven na uzlu ${node_name}.${COLOR_NC}"
        ALL_SERVICES_READY=false
    else
        echo -e "${COLOR_GREEN}Soubor var-lib-linstor.mount JE správně nastaven na uzlu ${node_name}.${COLOR_NC}"
    fi

    if [[ "$node_name" == "$PRIMARY_NODE" ]]; then
        echo -e "${COLOR_BLUE}Kontroluji /var/lib/linstor na primárním uzlu ${node_name}...${COLOR_NC}"
        if ! ssh "$node_ip" "findmnt /var/lib/linstor | grep -q '/dev/drbd/by-res/linstor_db/0' && systemctl is-active linstor-controller &> /dev/null"; then
            echo -e "${COLOR_RED}/var/lib/linstor NENÍ namountováno z DRBD nebo linstor-controller NENÍ aktivní na primárním uzlu.${COLOR_NC}"
            ALL_SERVICES_READY=false
        else
            echo -e "${COLOR_GREEN}/var/lib/linstor JE namountováno z DRBD a linstor-controller JE aktivní na primárním uzlu.${COLOR_NC}"
        fi
    else
        echo -e "${COLOR_BLUE}Kontroluji /var/lib/linstor na vedlejším uzlu ${node_name}...${COLOR_NC}"
        # Zkontrolujte, zda je adresář prázdný a imutabilní
        if ! ssh "$node_ip" "test -z \"\$(ls -A /var/lib/linstor)\" && lsattr /var/lib/linstor | grep -q 'i'"; then
            echo -e "${COLOR_RED}/var/lib/linstor NENÍ připraveno na vedlejším uzlu ${node_name} (prázdné a imutabilní).${COLOR_NC}"
            ALL_SERVICES_READY=false
        else
            echo -e "${COLOR_GREEN}/var/lib/linstor JE připraveno na vedlejším uzlu ${node_name}.${COLOR_NC}"
        fi
    fi
done

if ! $ALL_SERVICES_READY; then
    read -p "$(echo -e "${COLOR_YELLOW}Služby pro Linstor HA nejsou správně nastaveny na všech uzlech. Chceš je připravit? (ano/ne): ${COLOR_NC}")" choice
    if [[ "$choice" != "ano" ]]; then
        echo -e "${COLOR_RED}Příprava služeb Linstor HA přerušena uživatelem.${COLOR_NC}"
        exit 1
    fi

    echo -e "${COLOR_BLUE}Zastavuji linstor-controller na primárním uzlu ${PRIMARY_NODE}...${COLOR_NC}"
    if ssh "$PRIMARY_NODE_IP" "systemctl is-active linstor-controller &> /dev/null"; then
        run_command_quiet "ssh $PRIMARY_NODE_IP 'systemctl stop linstor-controller'" \
            "Linstor-controller zastaven na primárním uzlu." \
            "Chyba při zastavení linstor-controller na primárním uzlu. Zkontroluj ručně."
    else
        echo -e "${COLOR_GREEN}Linstor-controller již není aktivní na primárním uzlu.${COLOR_NC}"
    fi

    for i in "${!NODES[@]}"; do
        node_name="${NODES[$i]}"
        node_ip="${NODE_IPS[$i]}"
        echo -e "${COLOR_BLUE}Vytvářím službu pro DRBD mount adresáře s linstor databází na uzlu ${node_name} (${node_ip})...${COLOR_NC}"
        if ! ssh "$node_ip" "test -f /etc/systemd/system/var-lib-linstor.mount && grep -q '/dev/drbd/by-res/linstor_db/0' /etc/systemd/system/var-lib-linstor.mount"; then
            run_command_quiet "ssh $node_ip 'cat << EOF_INNER > /etc/systemd/system/var-lib-linstor.mount
[Unit]
Description=Filesystem for the LINSTOR controller

[Mount]
# you can use the minor like /dev/drbdX or the udev symlink
What=/dev/drbd/by-res/linstor_db/0
Where=/var/lib/linstor
EOF_INNER'" \
                "Soubor var-lib-linstor.mount vytvořen na uzlu ${node_name}." \
                "Chyba při vytváření souboru var-lib-linstor.mount na uzlu ${node_name}. Zkontroluj ručně."
        else
            echo -e "${COLOR_GREEN}Soubor var-lib-linstor.mount již existuje a je správný na uzlu ${node_name}. Přeskakuji vytváření.${COLOR_NC}"
        fi

        if [[ "$node_name" == "$PRIMARY_NODE" ]]; then
            echo -e "${COLOR_BLUE}Příprava /var/lib/linstor na primárním uzlu ${PRIMARY_NODE}...${COLOR_NC}"
            if ! ssh "$node_ip" "findmnt /var/lib/linstor | grep -q '/dev/drbd/by-res/linstor_db/0'"; then
                run_command_quiet "ssh $node_ip 'mv /var/lib/linstor{,.orig} && mkdir /var/lib/linstor && chattr +i /var/lib/linstor && drbdadm primary linstor_db && mkfs.ext4 -F /dev/drbd/by-res/linstor_db/0 && systemctl start var-lib-linstor.mount && cp -r /var/lib/linstor.orig/* /var/lib/linstor && rm -rf /var/lib/linstor.orig'" \
                    "Příprava /var/lib/linstor dokončena na primárním uzlu." \
                    "Chyba při přípravě /var/lib/linstor na primárním uzlu. Zkontroluj ručně."
            else
                echo -e "${COLOR_GREEN}/var/lib/linstor je již namountováno z DRBD na primárním uzlu. Přeskakuji přípravu adresáře.${COLOR_NC}"
            fi
            # Spuštění controlleru by mělo být nezávislé na existenci mountu
            run_command_quiet "ssh $node_ip 'systemctl start linstor-controller'" \
                "Linstor-controller nastartován na primárním uzlu." \
                "Chyba při startu linstor-controller na primárním uzlu. Zkontroluj ručně."
        else
            echo -e "${COLOR_BLUE}Příprava /var/lib/linstor na vedlejším uzlu ${node_name}...${COLOR_NC}"
            if ! ssh "$node_ip" "test -z \"\$(ls -A /var/lib/linstor)\" && lsattr /var/lib/linstor | grep -q 'i'"; then
                run_command_quiet "ssh $node_ip 'rm -rf /var/lib/linstor/* && chattr +i /var/lib/linstor'" \
                    "Příprava /var/lib/linstor dokončena na vedlejším uzlu ${node_name}." \
                    "Chyba při přípravě /var/lib/linstor na vedlejším uzlu ${node_name}. Zkontroluj ručně."
            else
                echo -e "${COLOR_GREEN}Upozornění: /var/lib/linstor na vedlejším uzlu ${node_name} není prázdné a imutabilní. Zkontroluj ručně, pokud to není očekávaný stav.${COLOR_NC}"
            fi
        fi
    done
else
    echo -e "${COLOR_GREEN}Všechny služby pro Linstor HA jsou správně nastaveny na všech uzlech. Přeskakuji krok.${COLOR_NC}"
fi
checkpoint "Příprava /var/lib/linstor a spuštění controlleru na primárním uzlu dokončena."

echo -e "${COLOR_BLUE}Kontroluji stav Linstor nodů na primárním uzlu...${COLOR_NC}"
run_command_verbose "ssh $PRIMARY_NODE_IP 'linstor node l'" \
    "Linstor nody jsou viditelné a databáze je HA." \
    "Chyba při kontrole Linstor nodů nebo databáze není HA. Zkontroluj ručně."

###
## 11. Instalace drbd-reactor a konfigurace

echo -e "${COLOR_BLUE}### Krok 11: Instalace drbd-reactor a konfigurace pro automatické spouštění služeb. ###${COLOR_NC}"

ALL_REACTOR_READY=true
for i in "${!NODES[@]}"; do
    node_name="${NODES[$i]}"
    node_ip="${NODE_IPS[$i]}"
    echo -e "${COLOR_BLUE}Kontroluji instalaci a konfiguraci drbd-reactor na uzlu ${node_name} (${node_ip})...${COLOR_NC}"
    if ! ssh "$node_ip" "dpkg -s drbd-reactor &> /dev/null && test -f /etc/drbd-reactor.d/linstor_db.toml && grep -q 'linstor_db.toml' /etc/drbd-reactor.d/linstor_db.toml && systemctl is-enabled drbd-reactor &> /dev/null && systemctl is-active drbd-reactor &> /dev/null"; then
        echo -e "${COLOR_RED}Drbd-reactor NENÍ správně nainstalován nebo nakonfigurován/spuštěn na uzlu ${node_name}.${COLOR_NC}"
        ALL_REACTOR_READY=false
    else
        echo -e "${COLOR_GREEN}Drbd-reactor JE správně nainstalován a nakonfigurován/spuštěn na uzlu ${node_name}.${COLOR_NC}"
    fi
done

if ! $ALL_REACTOR_READY; then
    read -p "$(echo -e "${COLOR_YELLOW}Drbd-reactor není správně nastaven na všech uzlech. Chceš ho nainstalovat a nakonfigurovat? (ano/ne): ${COLOR_NC}")" choice
    if [[ "$choice" != "ano" ]]; then
        echo -e "${COLOR_RED}Instalace a konfigurace drbd-reactor přerušena uživatelem.${COLOR_NC}"
        exit 1
    fi

    for i in "${!NODES[@]}"; do
        node_name="${NODES[$i]}"
        node_ip="${NODE_IPS[$i]}"
        echo -e "${COLOR_BLUE}Instaluji drbd-reactor na uzel ${node_name} (${node_ip})...${COLOR_NC}"
        if ! ssh "$node_ip" "dpkg -s drbd-reactor &> /dev/null"; then
            run_command_quiet "ssh $node_ip 'apt install drbd-reactor -y'" \
                "Drbd-reactor nainstalován na uzlu ${node_name}." \
                "Chyba při instalaci drbd-reactor na uzlu ${node_name}. Zkontroluj ručně."
        else
            echo -e "${COLOR_GREEN}Drbd-reactor je již nainstalován na uzlu ${node_name}. Přeskakuji instalaci.${COLOR_NC}"
        fi

        echo -e "${COLOR_BLUE}Vytvářím config pro drbd-reactor na uzlu ${node_name} (${node_ip})...${COLOR_NC}"
        if ! ssh "$node_ip" "test -f /etc/drbd-reactor.d/linstor_db.toml && grep -q 'linstor_db.toml' /etc/drbd-reactor.d/linstor_db.toml"; then
            run_command_quiet "ssh $node_ip 'mkdir -p /etc/drbd-reactor.d/ && cat << EOF_INNER > /etc/drbd-reactor.d/linstor_db.toml
[[promoter]]
[promoter.resources.linstor_db]
start = [\"var-lib-linstor.mount\", \"linstor-controller.service\"]
EOF_INNER'" \
                "Config drbd-reactor vytvořen na uzlu ${node_name}." \
                "Chyba při vytváření configu drbd-reactor na uzlu ${node_name}. Zkontroluj ručně."
        else
            echo -e "${COLOR_GREEN}Config drbd-reactor pro linstor_db již existuje na uzlu ${node_name}. Přeskakuji vytváření.${COLOR_NC}"
        fi

        echo -e "${COLOR_BLUE}Restartuji a povoluji drbd-reactor na uzlu ${node_name} (${node_ip})...${COLOR_NC}"
        if ! ssh "$node_ip" "systemctl is-enabled drbd-reactor &> /dev/null" && ssh "$node_ip" "systemctl is-active drbd-reactor &> /dev/null"; then
            run_command_quiet "ssh $node_ip 'systemctl restart drbd-reactor && systemctl enable drbd-reactor'" \
                "Drbd-reactor restartován a povolen na uzlu ${node_name}." \
                "Chyba při restartu/povolení drbd-reactor na uzlu ${node_name}. Zkontroluj ručně."
        else
            echo -e "${COLOR_GREEN}Drbd-reactor je již povolen a aktivní na uzlu ${node_name}.${COLOR_NC}"
        fi
        
        echo -e "${COLOR_BLUE}Kontroluji stav drbd-reactor na uzlu ${node_name} (${node_ip})...${COLOR_NC}"
        run_command_verbose "ssh $node_ip 'drbd-reactorctl'" \
            "Drbd-reactor funguje na uzlu ${node_name}." \
            "Chyba při kontrole drbd-reactor na uzlu ${node_name}. Zkontroluj ručně."
    done
else
    echo -e "${COLOR_GREEN}Drbd-reactor je již nainstalován a nakonfigurován na všech uzlech. Přeskakuji krok.${COLOR_NC}"
fi
checkpoint "Drbd-reactor nainstalován a nakonfigurován na všech uzlech."

###
## 12. Nastavení linstor-satellite pro zachování lokálních resources

echo -e "${COLOR_BLUE}### Krok 12: Nastavení linstor-satellite pro zachování lokálních resources po rebootu. ###${COLOR_NC}"

ALL_SATELLITE_CONFIGURED=true
LINSTOR_KEEP_RES_VALUE="linstor_db" # Hodnota, kterou chceme nastavit

for i in "${!NODES[@]}"; do
    node_name="${NODES[$i]}"
    node_ip="${NODE_IPS[$i]}"
    
    echo -e "${COLOR_BLUE}Kontroluji konfiguraci linstor-satellite na uzlu ${node_name} (${node_ip})...${COLOR_NC}"
    
    # Kontrola, zda je hodnota Environment=LS_KEEP_RES=linstor_db přítomna v konfiguraci služby
    # systemctl show zobrazuje sloučenou konfiguraci, včetně override souborů
    if ssh "$node_ip" "systemctl show linstor-satellite | grep -qE 'Environment=LS_KEEP_RES=${LINSTOR_KEEP_RES_VALUE}'"; then
        echo -e "${COLOR_GREEN}Služba linstor-satellite JE správně upravena na uzlu ${node_name}.${COLOR_NC}"
    else
        echo -e "${COLOR_RED}Služba linstor-satellite NENÍ správně upravena na uzlu ${node_name}.${COLOR_NC}"
        ALL_SATELLITE_CONFIGURED=false
    fi
done

if ! $ALL_SATELLITE_CONFIGURED; then
    read -p "$(echo -e "${COLOR_YELLOW}Linstor-satellite není správně nakonfigurován na všech uzlech. Chceš ho upravit? (ano/ne): ${COLOR_NC}")" choice
    if [[ "$choice" != "ano" ]]; then
        echo -e "${COLOR_RED}Úprava linstor-satellite přerušena uživatelem.${COLOR_NC}"
        exit 1
    fi

    for i in "${!NODES[@]}"; do
        node_name="${NODES[$i]}"
        node_ip="${NODE_IPS[$i]}"
        
        echo -e "${COLOR_BLUE}Upravuji službu linstor-satellite na uzlu ${node_name} (${node_ip})...${COLOR_NC}"
        
        local override_dir="/etc/systemd/system/linstor-satellite.service.d"
        local override_file="${override_dir}/override.conf"

        # Vytvoření adresáře pro override soubory, pokud neexistuje
        # Používáme run_command_quiet pro tichý výstup
        run_command_quiet "ssh $node_ip 'sudo mkdir -p ${override_dir}'" \
            "Adresář ${override_dir} vytvořen/existuje na uzlu ${node_name}." \
            "Chyba při vytváření adresáře ${override_dir} na uzlu ${node_name}."

        # Vytvoření nebo přepsání override souboru s požadovaným nastavením
        # Obsah '[Service]\nEnvironment=LS_KEEP_RES=linstor_db'
        run_command_quiet "ssh $node_ip 'echo -e \"[Service]\nEnvironment=LS_KEEP_RES=${LINSTOR_KEEP_RES_VALUE}\" | sudo tee ${override_file} > /dev/null'" \
            "Služba linstor-satellite upravena v ${override_file} na uzlu ${node_name}." \
            "Chyba při úpravě služby linstor-satellite na uzlu ${node_name}. Zkontroluj ručně."
        
        # Reload systemd daemonu, aby se změny projevily
        run_command_quiet "ssh $node_ip 'sudo systemctl daemon-reload'" \
            "systemd daemon reloadnut na uzlu ${node_name}." \
            "Chyba při reloadu systemd daemonu na uzlu ${node_name}."

        # Kontrola, zda se změny po úpravě a reloadu projevily
        if ssh "$node_ip" "systemctl show linstor-satellite | grep -qE 'Environment=LS_KEEP_RES=${LINSTOR_KEEP_RES_VALUE}'"; then
            echo -e "${COLOR_GREEN}Ověření OK: Služba linstor-satellite je správně upravena na uzlu ${node_name}.${COLOR_NC}"
        else
            echo -e "${COLOR_RED}Ověření SELHALO: Služba linstor-satellite NENÍ správně upravena na uzlu ${node_name} i po pokusu o úpravu.${COLOR_NC}"
            ALL_SATELLITE_CONFIGURED=false # Pokud se i po úpravě něco nepovedlo, nastavíme flag
        fi

    done
else
    echo -e "${COLOR_GREEN}Linstor-satellite je již nastaven pro zachování resources na všech uzlech. Přeskakuji krok.${COLOR_NC}"
fi

# Závěrečný checkpoint by měl reflektovat celkový stav
if ! $ALL_SATELLITE_CONFIGURED; then
    checkpoint "Konfigurace linstor-satellite selhala na některých uzlech. Zkontroluj ručně."
    # Můžete zde přidat exit 1, pokud chcete, aby skript zastavil při selhání
    # exit 1
else
    checkpoint "Linstor-satellite nastaven pro zachování resources."
fi

###
## 13. Vytvoření linstor-client.conf

echo -e "${COLOR_BLUE}### Krok 13: Vytvoření linstor-client.conf pro zjednodušení práce s Linstorem. ###${COLOR_NC}"

# Seznam IP adres uzlů oddělených čárkou pro konfiguraci controllerů
CONTROLLERS_IPS=$(IFS=,; echo "${NODE_IPS[*]}")

ALL_CLIENT_CONFIGURED=true
for i in "${!NODES[@]}"; do
    node_name="${NODES[$i]}"
    node_ip="${NODE_IPS[$i]}"
    echo -e "${COLOR_BLUE}Kontroluji /etc/linstor/linstor-client.conf na uzlu ${node_name} (${node_ip})...${COLOR_NC}"
    if ! ssh "$node_ip" "test -f /etc/linstor/linstor-client.conf && grep -q \"controllers=${CONTROLLERS_IPS}\" /etc/linstor/linstor-client.conf"; then
        echo -e "${COLOR_RED}Config linstor-client.conf NENÍ správně vytvořen na uzlu ${node_name}.${COLOR_NC}"
        ALL_CLIENT_CONFIGURED=false
    else
        echo -e "${COLOR_GREEN}Config linstor-client.conf JE správně vytvořen na uzlu ${node_name}.${COLOR_NC}"
    fi
done

if ! $ALL_CLIENT_CONFIGURED; then
    read -p "$(echo -e "${COLOR_YELLOW}Linstor-client.conf není správně nastaven na všech uzlech. Chceš ho vytvořit? (ano/ne): ${COLOR_NC}")" choice
    if [[ "$choice" != "ano" ]]; then
        echo -e "${COLOR_RED}Vytváření linstor-client.conf přerušeno uživatelem.${COLOR_NC}"
        exit 1
    fi

    for i in "${!NODES[@]}"; do
        node_name="${NODES[$i]}"
        node_ip="${NODE_IPS[$i]}"
        echo -e "${COLOR_BLUE}Vytvářím /etc/linstor/linstor-client.conf na uzlu ${node_name} (${node_ip})...${COLOR_NC}"
        run_command_quiet "ssh $node_ip 'mkdir -p /etc/linstor && cat << EOF_INNER > /etc/linstor/linstor-client.conf
[global]
controllers=${CONTROLLERS_IPS}
EOF_INNER'" \
            "Config linstor-client.conf vytvořen na uzlu ${node_name}." \
            "Chyba při vytváření linstor-client.conf na uzlu ${node_name}. Zkontroluj ručně."
    done
else
    echo -e "${COLOR_GREEN}Linstor-client.conf je již vytvořen na všech uzlech. Přeskakuji krok.${COLOR_NC}"
fi

echo -e "${COLOR_YELLOW}Doporučení: Pro lepší správu zvažte přidání záznamů hostname a IP adres do /etc/hosts na všech uzlech, pokud jste tak ještě neučinili.${COLOR_NC}"
checkpoint "Linstor-client.conf vytvořen na všech uzlech."

###
## 14. Dokončení nastavení StoragePoolu a definice resource pro běžný provoz

echo -e "${COLOR_BLUE}### Krok 14: Nastavení dalších StoragePoolů a ResourceGroup pro běžný provoz. ###${COLOR_NC}"

# Tyto proměnné budou globální pro tento krok, aby se nemuselo ptát pro každý uzel zvlášť
# a aby bylo možné vytvořit jen jednu Resource Group
read -p "$(echo -e "${COLOR_YELLOW}Zadej název ZFS poolu pro běžná DRBD data (např. 'fast' nebo 'tank') - toto je globální pro VŠECHNY uzly: ${COLOR_NC}")" GLOBAL_ZFS_DATA_POOL_NAME
read -p "$(echo -e "${COLOR_YELLOW}Zadej název Linstor StoragePoolu pro data (např. 'pooldata' nebo 'pool${GLOBAL_ZFS_DATA_POOL_NAME}'): ${COLOR_NC}")" GLOBAL_LINSTOR_DATA_POOL_NAME
read -p "$(echo -e "${COLOR_YELLOW}Zadej název Resource Group pro data (např. 'rgdata' nebo 'rg${GLOBAL_ZFS_DATA_POOL_NAME}'): ${COLOR_NC}")" GLOBAL_LINSTOR_DATA_RG_NAME
read -p "$(echo -e "${COLOR_YELLOW}Kolik replik DRBD dat bude mít tato ResourceGroup? (např. 2 pro 2 datové uzly, nebo ${#NODES[@]} pro všechny uzly): ${COLOR_NC}")" GLOBAL_PLACE_COUNT

ALL_DATA_STORAGE_READY=true
for i in "${!NODES[@]}"; do
    node_name="${NODES[$i]}"
    node_ip="${NODE_IPS[$i]}"
    echo -e "\n${COLOR_BLUE}Kontroluji storage pro uzel ${node_name}:${COLOR_NC}"
    
    echo -e "${COLOR_BLUE}Kontroluji ZFS dataset ${GLOBAL_ZFS_DATA_POOL_NAME}/linstor na uzlu ${node_name} (${node_ip})...${COLOR_NC}"
    if ! ssh "$node_ip" "zfs list ${GLOBAL_ZFS_DATA_POOL_NAME}/linstor &> /dev/null"; then
        echo -e "${COLOR_RED}ZFS dataset ${GLOBAL_ZFS_DATA_POOL_NAME}/linstor NENÍ vytvořen na uzlu ${node_name}.${COLOR_NC}"
        ALL_DATA_STORAGE_READY=false
    else
        echo -e "${COLOR_GREEN}ZFS dataset ${GLOBAL_ZFS_DATA_POOL_NAME}/linstor JE vytvořen na uzlu ${node_name}.${COLOR_NC}"
    fi

    echo -e "${COLOR_BLUE}Kontroluji Linstor StoragePool '${GLOBAL_LINSTOR_DATA_POOL_NAME}' na uzlu ${node_name} (${node_ip})...${COLOR_NC}"
    # Změněno: Odstraněno --output-version=1
    if ! ssh "$PRIMARY_NODE_IP" "linstor sp list | grep -q \"^|\\s*${node_name}\\s*|\\s*${GLOBAL_LINSTOR_DATA_POOL_NAME}\\s*|\""; then
        echo -e "${COLOR_RED}Linstor StoragePool '${GLOBAL_LINSTOR_DATA_POOL_NAME}' NENÍ vytvořen na uzlu ${node_name}.${COLOR_NC}"
        ALL_DATA_STORAGE_READY=false
    else
        echo -e "${COLOR_GREEN}Linstor StoragePool '${GLOBAL_LINSTOR_DATA_POOL_NAME}' JE vytvořen na uzlu ${node_name}.${COLOR_NC}"
    fi
done

echo -e "${COLOR_BLUE}Kontroluji ResourceGroup '${GLOBAL_LINSTOR_DATA_RG_NAME}'...${COLOR_NC}"
# Změněno: Odstraněno --output-version=1
if ! ssh "$PRIMARY_NODE_IP" "linstor rg list | grep -q \"^|\\s*${GLOBAL_LINSTOR_DATA_RG_NAME}\\s*|\""; then
    echo -e "${COLOR_RED}ResourceGroup '${GLOBAL_LINSTOR_DATA_RG_NAME}' NENÍ vytvořena.${COLOR_NC}"
    ALL_DATA_STORAGE_READY=false
else
    echo -e "${COLOR_GREEN}ResourceGroup '${GLOBAL_LINSTOR_DATA_RG_NAME}' JE vytvořena.${COLOR_NC}"
fi

if ! $ALL_DATA_STORAGE_READY; then
    read -p "$(echo -e "${COLOR_YELLOW}Některé komponenty datového úložiště nebo ResourceGroup chybí. Chceš je vytvořit a nastavit? (ano/ne): ${COLOR_NC}")" choice
    if [[ "$choice" != "ano" ]]; then
        echo -e "${COLOR_RED}Vytváření datového úložiště a ResourceGroup přerušeno uživatelem.${COLOR_NC}"
        exit 1
    fi

    for i in "${!NODES[@]}"; do
        node_name="${NODES[$i]}"
        node_ip="${NODE_IPS[$i]}"
        echo -e "${COLOR_BLUE}Nastavení storage pro uzel ${node_name}:${COLOR_NC}"
        
        echo -e "${COLOR_BLUE}Vytvářím ZFS dataset ${GLOBAL_ZFS_DATA_POOL_NAME}/linstor na uzlu ${node_name} (${node_ip})...${COLOR_NC}"
        if ! ssh "$node_ip" "zfs list ${GLOBAL_ZFS_DATA_POOL_NAME}/linstor &> /dev/null"; then
            run_command_quiet "ssh $node_ip 'zfs create ${GLOBAL_ZFS_DATA_POOL_NAME}/linstor'" \
                "ZFS dataset ${GLOBAL_ZFS_DATA_POOL_NAME}/linstor vytvořen na uzlu ${node_name}." \
                "Chyba při vytváření ZFS datasetu na uzlu ${node_name}. Zkontroluj ručně."
        else
            echo -e "${COLOR_GREEN}ZFS dataset ${GLOBAL_ZFS_DATA_POOL_NAME}/linstor již existuje na uzlu ${node_name}.${COLOR_NC}"
        fi

        echo -e "${COLOR_BLUE}Vytvářím Linstor StoragePool '${GLOBAL_LINSTOR_DATA_POOL_NAME}' na uzlu ${node_name} (${node_ip})...${COLOR_NC}"
        # Změněno: Odstraněno --output-version=1
        if ! ssh "$PRIMARY_NODE_IP" "linstor sp list | grep -q \"^|\\s*${node_name}\\s*|\\s*${GLOBAL_LINSTOR_DATA_POOL_NAME}\\s*|\""; then
            run_command_quiet "ssh $PRIMARY_NODE_IP 'linstor storage-pool create zfs $node_name $GLOBAL_LINSTOR_DATA_POOL_NAME ${GLOBAL_ZFS_DATA_POOL_NAME}/linstor'" \
                "Linstor StoragePool '${GLOBAL_LINSTOR_DATA_POOL_NAME}' vytvořen na uzlu ${node_name}." \
                "Chyba při vytváření Linstor StoragePoolu na uzlu ${node_name}. Zkontroluj ručně."
        else
            echo -e "${COLOR_GREEN}Linstor StoragePool '${GLOBAL_LINSTOR_DATA_POOL_NAME}' již existuje na uzlu ${node_name}. Přeskakuji.${COLOR_NC}"
        fi
    done

    echo -e "${COLOR_BLUE}Vytvářím ResourceGroup '${GLOBAL_LINSTOR_DATA_RG_NAME}'...${COLOR_NC}"
    # Změněno: Odstraněno --output-version=1
    if ! ssh "$PRIMARY_NODE_IP" "linstor rg list | grep -q \"^|\\s*${GLOBAL_LINSTOR_DATA_RG_NAME}\\s*|\""; then
        run_command_quiet "ssh $PRIMARY_NODE_IP 'linstor resource-group create $GLOBAL_LINSTOR_DATA_RG_NAME --place-count $GLOBAL_PLACE_COUNT --storage-pool $GLOBAL_LINSTOR_DATA_POOL_NAME'" \
            "ResourceGroup '${GLOBAL_LINSTOR_DATA_RG_NAME}' vytvořena." \
            "Chyba při vytváření ResourceGroup '${GLOBAL_LINSTOR_DATA_RG_NAME}'. Zkontroluj ručně."

        run_command_quiet "ssh $PRIMARY_NODE_IP 'linstor resource-group set-property $GLOBAL_LINSTOR_DATA_RG_NAME StorDriver/ZfscreateOptions \"-b 32k\"'" \
            "Velikost bloků nastavena pro '${GLOBAL_LINSTOR_DATA_RG_NAME}'." \
            "Chyba při nastavování velikosti bloků. Zkontroluj ručně."

        run_command_quiet "ssh $PRIMARY_NODE_IP 'linstor volume-group create $GLOBAL_LINSTOR_DATA_RG_NAME'" \
            "Volume-group vytvořena pro '${GLOBAL_LINSTOR_DATA_RG_NAME}'." \
            "Chyba při vytváření volume-group. Zkontroluj ručně."

        run_command_quiet "ssh $PRIMARY_NODE_IP 'linstor resource-group set-property $GLOBAL_LINSTOR_DATA_RG_NAME StorPoolNameDrbdMeta $GLOBAL_LINSTOR_DATA_POOL_NAME'" \
            "Metadata pool nastaven pro '${GLOBAL_LINSTOR_DATA_RG_NAME}'." \
            "Chyba při nastavování metadat poolu. Zkontroluj ručně."
    else
        echo -e "${COLOR_GREEN}ResourceGroup '${GLOBAL_LINSTOR_DATA_RG_NAME}' již existuje. Přeskakuji vytváření a nastavování.${COLOR_NC}"
    fi
else
    echo -e "${COLOR_GREEN}StoragePool a ResourceGroup pro běžný provoz jsou nastaveny. Přeskakuji krok.${COLOR_NC}"
fi
checkpoint "StoragePool a ResourceGroup pro běžný provoz nastaveny."

###
## 15. Nastavení Proxmox storage.cfg

echo -e "${COLOR_BLUE}### Krok 15: Nastavení Proxmox storage.cfg pro viditelnost Linstor storage. ###${COLOR_NC}"

# Seznam IP adres controllerů oddělených čárkou pro Proxmox konfiguraci
PVE_CONTROLLERS_IPS=$(IFS=,; echo "${NODE_IPS[*]}") 

read -p "$(echo -e "${COLOR_YELLOW}Zadej název, pod kterým se bude Linstor úložiště zobrazovat v Proxmoxu (např. 'linstor-data'): ${COLOR_NC}")" proxmox_storage_name
read -p "$(echo -e "${COLOR_YELLOW}Zadej název Resource Group, kterou má Proxmox používat (např. 'rgdata'). To je Resource Group, kterou jsi vytvořil(a) v předchozím kroku pro DATA: ${COLOR_NC}")" proxmox_rg_name

STORAGE_CFG_READY=true
echo -e "${COLOR_BLUE}Kontroluji konfiguraci Linstor do /etc/pve/storage.cfg na primárním uzlu ${PRIMARY_NODE}...${COLOR_NC}"
if ! ssh "$PRIMARY_NODE_IP" "grep -q \"drbd: ${proxmox_storage_name}\" /etc/pve/storage.cfg && grep -q \"controller ${PVE_CONTROLLERS_IPS}\" /etc/pve/storage.cfg && grep -q \"resourcegroup ${proxmox_rg_name}\" /etc/pve/storage.cfg"; then
    echo -e "${COLOR_RED}Linstor storage '${proxmox_storage_name}' NENÍ správně přidán do Proxmox storage.cfg.${COLOR_NC}"
    STORAGE_CFG_READY=false
else
    echo -e "${COLOR_GREEN}Linstor storage '${proxmox_storage_name}' JE správně přidán do Proxmox storage.cfg.${COLOR_NC}"
fi

if ! $STORAGE_CFG_READY; then
    read -p "$(echo -e "${COLOR_YELLOW}Linstor storage není správně nakonfigurován v Proxmoxu. Chceš ho přidat do /etc/pve/storage.cfg? (ano/ne): ${COLOR_NC}")" choice
    if [[ "$choice" != "ano" ]]; then
        echo -e "${COLOR_RED}Nastavení Proxmox storage.cfg přerušeno uživatelem.${COLOR_NC}"
        exit 1
    fi

    echo -e "${COLOR_BLUE}Přidávám konfiguraci Linstor do /etc/pve/storage.cfg na primárním uzlu ${PRIMARY_NODE}...${COLOR_NC}"
    run_command_quiet "ssh $PRIMARY_NODE_IP 'cat << EOF_INNER >> /etc/pve/storage.cfg
drbd: $proxmox_storage_name
        content images, rootdir
        controller ${PVE_CONTROLLERS_IPS}
        resourcegroup $proxmox_rg_name
EOF_INNER'" \
        "Linstor storage přidán do Proxmox storage.cfg." \
        "Chyba při přidávání Linstor storage do Proxmox storage.cfg. Zkontroluj ručně."
else
    echo -e "${COLOR_GREEN}Proxmox storage.cfg je již upraven. Přeskakuji krok.${COLOR_NC}"
fi
checkpoint "Proxmox storage.cfg upraven."

###
## FINISH!

echo -e "${COLOR_GREEN}===========================================${COLOR_NC}"
echo -e "${COLOR_GREEN} Instalace Linstor DRBD na Proxmox VE cluster dokončena!${COLOR_NC}"
echo -e "${COLOR_GREEN}===========================================${COLOR_NC}"
echo -e "${COLOR_YELLOW}Nyní bys měl(a) být schopni spravovat Linstor disky z Proxmox WebUI.${COLOR_NC}"
echo -e "${COLOR_YELLOW}Nezapomeň zkontrolovat dostupnost nového úložiště v Proxmox GUI.${COLOR_NC}"
echo -e "${COLOR_YELLOW}V případě problémů zkontroluj logy Linstor a DRBD na jednotlivých uzlech.${COLOR_NC}"

exit 0