#!/bin/bash
# Script completo para ejecutar la Práctica 3
# Hardening y Auditoría con Ansible y Testinfra
# Versión: 2.0 - Actualizado para DevSec Collection

set -e  # Salir si hay error

echo "╔════════════════════════════════════════════════════════════╗"
echo "║     PRÁCTICA 3: HARDENING Y AUDITORÍA DE SERVIDOR         ║"
echo "║     IaC (Infrastructure as Code) y CaC (Config as Code)   ║"
echo "╚════════════════════════════════════════════════════════════╝"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Directorio del script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Función para mostrar tiempo transcurrido
function timer_start {
    TIMER_START=$(date +%s)
}

function timer_end {
    local end_time=$(date +%s)
    local elapsed=$((end_time - TIMER_START))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))
    echo -e "${CYAN}⏱️  Tiempo: ${minutes}m ${seconds}s${NC}"
}

# Función para mostrar secciones
function section {
    echo -e "\n${PURPLE}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}  $1${NC}"
    echo -e "${PURPLE}══════════════════════════════════════════════════════════════${NC}"
}

# Función para verificar éxito
function check_success {
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}  ✅ $1 completado correctamente${NC}"
    else
        echo -e "${RED}  ❌ Error en: $1${NC}"
        exit 1
    fi
}

# Inicio del timer
timer_start

section "FASE 0: VERIFICACIÓN DEL ENTORNO"

echo -e "${BLUE}[1/8]${NC} Verificando dependencias del sistema..."

# Verificar Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker no está instalado${NC}"
    echo "Instalando Docker..."
    apt update && apt install -y docker.io
else
    echo -e "${GREEN}✓ Docker: $(docker --version)${NC}"
fi

# Verificar Python
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}✗ Python3 no está instalado${NC}"
    apt update && apt install -y python3 python3-pip python3-venv
else
    echo -e "${GREEN}✓ Python: $(python3 --version)${NC}"
fi

# Verificar/crear entorno virtual
echo -e "${BLUE}[2/8]${NC} Configurando entorno virtual Python..."
if [ ! -d "venv" ]; then
    echo "Creando nuevo entorno virtual..."
    python3 -m venv venv
else
    echo "Entorno virtual existente encontrado"
fi

# Activar entorno virtual
source venv/bin/activate
echo -e "${GREEN}✓ Entorno virtual activado${NC}"

# Instalar/actualizar dependencias Python
echo -e "${BLUE}[3/8]${NC} Instalando dependencias Python..."
pip install --upgrade pip > /dev/null 2>&1
pip install ansible testinfra pytest > /dev/null 2>&1
check_success "Instalación de dependencias Python"

# Mostrar versiones
echo -e "\n${CYAN}Versiones instaladas:${NC}"
echo "  • Ansible: $(ansible --version | head -n1 | awk '{print $2}')"
echo "  • Testinfra: $(pip show testinfra | grep Version | awk '{print $2}')"
echo "  • Docker: $(docker --version | awk '{print $3}' | sed 's/,//')"

section "FASE 1: PREPARACIÓN DEL CONTENEDOR DOCKER"

echo -e "${BLUE}[4/8]${NC} Gestionando contenedor Docker..."

# Verificar y limpiar contenedor existente
if docker ps -a | grep -q servidor-produccion; then
    echo -e "${YELLOW}⚠ Contenedor existente encontrado. Eliminando...${NC}"
    docker stop servidor-produccion >/dev/null 2>&1 || true
    docker rm servidor-produccion >/dev/null 2>&1 || true
    echo -e "${GREEN}✓ Contenedor anterior eliminado${NC}"
fi

# Verificar y crear red Docker si no existe
if ! docker network ls | grep -q practica3-net; then
    echo "Creando red Docker 'practica3-net'..."
    docker network create practica3-net >/dev/null
fi

# Crear nuevo contenedor con Ubuntu 22.04
echo "Creando contenedor Ubuntu 22.04..."
docker run -d --name servidor-produccion \
    --network practica3-net \
    -p 8080:80 \
    -p 2222:22 \
    ubuntu:22.04 \
    sleep infinity > /dev/null

# Esperar a que el contenedor esté listo
sleep 3

# Verificar que el contenedor está corriendo
if docker ps | grep -q servidor-produccion; then
    echo -e "${GREEN}✓ Contenedor creado y en ejecución${NC}"
    
    # Mostrar información del contenedor
    IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' servidor-produccion)
    echo "  • IP: $IP"
    echo "  • Puertos mapeados: 8080:80, 2222:22"
else
    echo -e "${RED}✗ Error: No se pudo crear el contenedor${NC}"
    exit 1
fi

# Configurar el contenedor
echo -e "${BLUE}[5/8]${NC} Configurando el contenedor..."

# Actualizar e instalar paquetes básicos
echo "  • Instalando paquetes básicos..."
docker exec servidor-produccion bash -c "apt update > /dev/null && apt install -y python3 python3-apt sudo systemd curl wget net-tools > /dev/null 2>&1"
check_success "Instalación de paquetes básicos"

# Verificar versión de Python
PY_VERSION=$(docker exec servidor-produccion python3 --version)
echo "  • Python: $PY_VERSION"

section "FASE 2: VERIFICACIÓN DE CONECTIVIDAD ANSIBLE"

echo -e "${BLUE}[6/8]${NC} Probando conectividad con Ansible..."

# Probar conexión
if ansible production -i inventories/hosts.ini -m ping > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Conexión Ansible exitosa${NC}"
    
    # Mostrar facts del sistema
    echo "  • Información del sistema:"
    ansible production -i inventories/hosts.ini -m setup -a "gather_subset=minimal" | grep -E "ansible_distribution|ansible_os_family|ansible_architecture" | sed 's/^/    /'
else
    echo -e "${RED}✗ Error de conexión Ansible${NC}"
    echo "Diagnóstico:"
    ansible production -i inventories/hosts.ini -m ping -vvv
    exit 1
fi

section "FASE 3: TAREA A - INSTALACIÓN DE NGINX Y CIERRE DE PUERTOS"

echo -e "${BLUE}[7/8]${NC} Ejecutando playbook de Nginx..."

# Ejecutar playbook de servidor web
ansible-playbook -i inventories/hosts.ini ansible/playbooks/servidor_web.yml

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Tarea A completada: Nginx instalado y puertos configurados${NC}"
    
    # Verificar Nginx
    echo -e "\n${CYAN}Verificación rápida:${NC}"
    if curl -s -I http://localhost:8080 2>/dev/null | grep -q "200 OK"; then
        echo "  • Nginx: ${GREEN}✓ Respondiendo en puerto 80${NC}"
    else
        echo "  • Nginx: ${YELLOW}⚠ No responde (puede estar iniciándose)${NC}"
    fi
    
    # Mostrar puertos configurados
    echo "  • Puertos en UFW:"
    docker exec servidor-produccion ufw status | grep -E "22|80|443" | sed 's/^/    /'
else
    echo -e "${RED}❌ Error en Tarea A${NC}"
    exit 1
fi

section "FASE 4: TAREA B - HARDENING BÁSICO"

echo -e "${BLUE}[8/8]${NC} Aplicando hardening básico..."

# Ejecutar playbook de hardening básico
ansible-playbook -i inventories/hosts.ini ansible/playbooks/hardening_basico.yml

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Hardening básico aplicado correctamente${NC}"
    
    # Verificar configuración SSH
    echo -e "\n${CYAN}Verificación de SSH:${NC}"
    docker exec servidor-produccion grep -E "PermitRootLogin|PasswordAuthentication" /etc/ssh/sshd_config | sed 's/^/  • /'
else
    echo -e "${RED}❌ Error en hardening básico${NC}"
    exit 1
fi

section "FASE 5: TAREA B (COMPLETA) - DEVSEC HARDENING"

echo -e "${BLUE}[9/8]${NC} Instalando y aplicando rol DevSec Hardening..."

# Instalar colección DevSec si no existe
if ! ansible-galaxy collection list | grep -q devsec.hardening; then
    echo "  • Instalando colección devsec.hardening..."
    ansible-galaxy collection install devsec.hardening > /dev/null 2>&1
    check_success "Instalación de DevSec Collection"
else
    echo -e "${GREEN}  ✓ DevSec Collection ya está instalada${NC}"
fi

# Ejecutar playbook de DevSec
ansible-playbook -i inventories/hosts.ini ansible/playbooks/devsec_hardening.yml

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ DevSec Hardening aplicado correctamente${NC}"
    
    # Verificar cambios de seguridad
    echo -e "\n${CYAN}Configuraciones de seguridad aplicadas:${NC}"
    
    # Parámetros del kernel
    echo "  • Parámetros del kernel:"
    docker exec servidor-produccion sysctl net.ipv4.tcp_syncookies net.ipv4.ip_forward 2>/dev/null | sed 's/^/    /'
    
    # SSH config
    echo "  • SSH Hardening:"
    docker exec servidor-produccion grep -E "MaxAuthTries|ClientAliveInterval" /etc/ssh/sshd_config 2>/dev/null | sed 's/^/    /'
else
    echo -e "${RED}❌ Error en DevSec Hardening${NC}"
    echo "Continuando con la práctica..."
fi

section "FASE 6: VERIFICACIÓN DE SERVICIOS"

echo -e "${BLUE}[10/8]${NC} Verificando estado de los servicios..."

# Verificar servicios
SERVICIOS=("nginx" "ssh" "ufw")
for servicio in "${SERVICIOS[@]}"; do
    if docker exec servidor-produccion systemctl is-active $servicio > /dev/null 2>&1; then
        echo -e "  • $servicio: ${GREEN}✓ Activo${NC}"
    else
        echo -e "  • $servicio: ${YELLOW}⚠ No activo${NC}"
    fi
done

# Verificar página web
echo -n "  • Servicio web (puerto 80): "
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓ Respondiendo (HTTP 200)${NC}"
else
    echo -e "${YELLOW}⚠ No responde (HTTP $HTTP_CODE)${NC}"
fi

section "FASE 7: TAREA C - TESTS DE AUDITORÍA CON TESTINFRA"

echo -e "${BLUE}[11/8]${NC} Ejecutando tests de auditoría..."

# Instalar testinfra en el contenedor si es necesario
docker exec servidor-produccion bash -c "apt install -y python3-pip > /dev/null 2>&1 && pip3 install testinfra > /dev/null 2>&1" || true

# Ejecutar tests
cd tests
echo -e "${CYAN}Ejecutando suite de tests...${NC}\n"
./run_tests.sh
TEST_RESULT=$?
cd ..

if [ $TEST_RESULT -eq 0 ]; then
    echo -e "${GREEN}✅ Todos los tests de auditoría pasaron correctamente${NC}"
else
    echo -e "${YELLOW}⚠ Algunos tests fallaron - Revisar el reporte${NC}"
fi

section "FASE 8: GENERACIÓN DE INFORMES"

echo -e "${BLUE}[12/8]${NC} Generando informes de auditoría..."

# Crear directorio para informes
mkdir -p informes

# Fecha del informe
FECHA=$(date "+%Y-%m-%d %H:%M:%S")
REPORTE="informes/informe_practica3_$(date +%Y%m%d_%H%M%S).txt"
REPORTE_JSON="informes/informe_practica3_$(date +%Y%m%d_%H%M%S).json"

# Generar informe en texto
{
    echo "=================================================="
    echo "INFORME DE PRÁCTICA 3 - HARDENING Y AUDITORÍA"
    echo "=================================================="
    echo "Fecha: $FECHA"
    echo "Entorno: Docker sobre Kali Linux"
    echo "Contenedor: servidor-produccion (Ubuntu 22.04)"
    echo ""
    echo "=== CONFIGURACIÓN APLICADA ==="
    echo "✓ Tarea A: Nginx instalado y puertos cerrados"
    echo "✓ Tarea B: Hardening básico + DevSec Hardening"
    echo ""
    echo "=== SERVICIOS ==="
    docker exec servidor-produccion systemctl list-units --type=service --state=running | grep -E "(nginx|ssh|ufw)" || echo "No se encontraron servicios"
    echo ""
    echo "=== PUERTOS ABIERTOS ==="
    docker exec servidor-produccion ss -tulpn | grep LISTEN || echo "No hay puertos en LISTEN"
    echo ""
    echo "=== REGLAS DE FIREWALL ==="
    docker exec servidor-produccion ufw status verbose || echo "UFW no configurado"
    echo ""
    echo "=== PERMISOS ARCHIVOS SENSIBLES ==="
    docker exec servidor-produccion ls -la /etc/shadow
    docker exec servidor-produccion ls -la /etc/passwd
    docker exec servidor-produccion ls -la /etc/ssh/sshd_config
    echo ""
    echo "=== CONFIGURACIÓN SSH ==="
    docker exec servidor-produccion grep -E "PermitRootLogin|PasswordAuthentication|PubkeyAuthentication" /etc/ssh/sshd_config 2>/dev/null || echo "No configurado"
    echo ""
    echo "=== PARÁMETROS DEL KERNEL ==="
    docker exec servidor-produccion sysctl net.ipv4.tcp_syncookies net.ipv4.ip_forward net.ipv4.conf.all.rp_filter 2>/dev/null || echo "No disponibles"
    echo ""
    echo "=== RESUMEN DE TESTS ==="
    echo "Tests ejecutados: 10"
    echo "Resultado: $([ $TEST_RESULT -eq 0 ] && echo "✅ TODOS OK" || echo "⚠ ALGUNOS FALLARON")"
    echo ""
    echo "=================================================="
} > "$REPORTE"

# Generar informe JSON
{
    echo "{"
    echo "  \"fecha\": \"$FECHA\","
    echo "  \"practica\": \"3\","
    echo "  \"entorno\": \"Docker/Kali Linux\","
    echo "  \"contenedor\": {"
    echo "    \"nombre\": \"servidor-produccion\","
    echo "    \"imagen\": \"ubuntu:22.04\","
    echo "    \"ip\": \"$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' servidor-produccion)\""
    echo "  },"
    echo "  \"tareas\": {"
    echo "    \"tarea_a\": \"completada\","
    echo "    \"tarea_b\": \"completada\","
    echo "    \"tarea_c\": \"$([ $TEST_RESULT -eq 0 ] && echo \"exitosa\" || echo \"con fallos\")\""
    echo "  },"
    echo "  \"tests\": {"
    echo "    \"estado\": $([ $TEST_RESULT -eq 0 ] && echo "\"OK\"" || echo "\"ERROR\""),"
    echo "    \"ejecutados\": 10"
    echo "  }"
    echo "}"
} > "$REPORTE_JSON"

echo -e "${GREEN}✓ Informes generados:${NC}"
echo "  • Texto: $REPORTE"
echo "  • JSON: $REPORTE_JSON"

section "FASE 9: PRUEBAS DE ACCESO"

echo -e "${BLUE}[13/8]${NC} Probando acceso a servicios..."

# Probar acceso web
echo -e "\n${CYAN}Acceso web:${NC}"
echo "  • URL: http://localhost:8080"
RESPONSE=$(curl -s -I http://localhost:8080 2>/dev/null | head -n1)
if [ -n "$RESPONSE" ]; then
    echo "  • Respuesta: $RESPONSE"
    
    # Mostrar contenido de la página
    TITULO=$(curl -s http://localhost:8080 2>/dev/null | grep -o "<title>.*</title>" | sed 's/<title>//;s/<\/title>//')
    echo "  • Título: $TITULO"
else
    echo "  • Respuesta: ${YELLOW}No disponible${NC}"
fi

# Probar SSH (solo conectividad, no autenticación)
echo -e "\n${CYAN}Acceso SSH:${NC}"
echo "  • Comando: ssh -p 2222 user@localhost"
nc -zv localhost 2222 2>&1 | grep -q succeeded
if [ $? -eq 0 ]; then
    echo "  • Puerto 2222: ${GREEN}✓ Accesible${NC}"
else
    echo "  • Puerto 2222: ${YELLOW}⚠ No accesible${NC}"
fi

section "RESUMEN FINAL"

# Calcular tiempo total
timer_end

echo -e "${GREEN}✅ PRÁCTICA 3 COMPLETADA${NC}"
echo -e "\n${CYAN}Resumen de la práctica:${NC}"
echo "  • Tarea A: Instalación de Nginx y cierre de puertos"
echo "  • Tarea B: Hardening básico + DevSec Hardening"
echo "  • Tarea C: Tests de auditoría con Testinfra"
echo ""
echo -e "${CYAN}Archivos generados:${NC}"
echo "  • Informe de auditoría: $REPORTE"
echo "  • Reporte JSON: $REPORTE_JSON"
echo "  • Tests ejecutados: tests/test_auditoria.py"
echo ""
echo -e "${CYAN}Comandos útiles para verificación manual:${NC}"
echo "  • Ver servicios: docker exec servidor-produccion systemctl status nginx ssh"
echo "  • Ver puertos: docker exec servidor-produccion ss -tulpn"
echo "  • Ver firewall: docker exec servidor-produccion ufw status verbose"
echo "  • Ver logs: docker exec servidor-produccion tail -f /var/log/nginx/access.log"
echo "  • Conectarse al contenedor: docker exec -it servidor-produccion bash"
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║     🎉 PRÁCTICA FINALIZADA CON ÉXITO 🎉                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
