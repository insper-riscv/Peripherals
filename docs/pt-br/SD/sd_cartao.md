# Cartão SD no SoC: acesso cru e com sistema de arquivos

🌐 [Português](../../pt-br/SD/sd_cartao.md) · [English](../../en/SD/sd_cartao.md)

## 1. Visão geral

O controlador [sd_native](sd_native.md) transfere um bloco de 512 bytes por comando, por polling, e não conhece formato de cartão. O software escolhe como o cartão é organizado, e a plataforma DOOM da DE0-CV usa duas formas, ambas só de leitura.

| Forma | Nome na plataforma | Variável de build | Cartão | Quem prepara |
| :--- | :--- | :--- | :--- | :--- |
| Cru (direct mapped) | `sdcard_direct_mapped` | `SDFS=raw` | Cabeçalho, índice e payload gravados a partir de setores fixos, sem sistema de arquivos | `scripts/sdwrite.py` do DOOM |
| FatFs | `sdcard_FatFs` | `SDFS=fatfs` | FAT32 comum, com os arquivos como arquivos | O explorador de arquivos do sistema |

| Critério | Cru | FatFs |
| :--- | :--- | :--- |
| Preparar o cartão | Um script apaga a tabela de partições e grava a imagem; o cartão deixa de ser FAT32 | Formatar e copiar arquivos, sem script |
| Código no SoC | Só o driver do sd_native, o cabeçalho e o índice | Driver, FatFs do ChaN e uma camada de disco fina |
| Trocar ou acrescentar um arquivo | Regravar o cartão inteiro | Copiar o arquivo |
| Leitura de um byte de um arquivo | Conta setor e deslocamento direto, sem percorrer a FAT | Percorre a FAT, com `FF_USE_FASTSEEK` para saltos longos |
| Uso do cartão em outros computadores | Não, o sistema o vê sem sistema de arquivos | Sim |

Em ambas as formas o controlador é o mesmo e a leitura de um bloco é a da seção 5.

## 2. Registradores do sd_native

A palavra do endereço é o número do registrador, e o byte é a palavra vezes 4. Na plataforma DOOM a base é `0x80008000`. Os bits de cada registrador, os erros e a temporização estão em [sd_native.md](sd_native.md), seção 4.

| Palavra | Endereço | Nome | Acesso | Uso no software |
| ---: | :--- | :--- | :--- | :--- |
| 0 | `0x80008000` | `ARG` | R/W | Argumento do próximo comando; para CMD17, o número do setor |
| 1 | `0x80008004` | `CMD` | R/W | A escrita inicia o comando: índice, formato da resposta, espera de ocupado e bloco de dados |
| 2 a 5 | `0x80008008` a `0x80008014` | `RESP0` a `RESP3` | R | Resposta curta em `RESP0` e `RESP1`; resposta longa (CID ou CSD) nas quatro palavras |
| 6 | `0x80008018` | `STATUS` | R/W1C | `CMD_BUSY`, `DATA_BUSY`, `CMD_DONE`, `DATA_DONE`, níveis de `CMD` e `DAT` |
| 7 | `0x8000801C` | `ERROR` | R/W1C | Dez erros persistentes de comando e de dados |
| 8 | `0x80008020` | `CONTROL` | R/W | `CLK_ENABLE`, `WIDE_BUS`, habilitação das interrupções, `ABORT` |
| 9 | `0x80008024` | `DIVIDER` | R/W | Divisor de `SD_CLK` |
| 10 | `0x80008028` | `TIMEOUT` | R/W | Prazo de espera por dado e por ocupado, em clocks do cartão |
| 11 | `0x8000802C` | `DATA` | R/W | Janela do buffer de 128 palavras; cada acesso avança `PTR` |
| 12 | `0x80008030` | `PTR` | R/W | Palavra do buffer apontada, de 0 a 127 |

Com o clock do núcleo em 100 MHz, o clock do cartão é

$$ f_{SD\_CLK} = \frac{100\ \text{MHz}}{2 \cdot (\text{DIVIDER} + 1)} $$

e o divisor 1 dá os 25 MHz do modo de velocidade padrão. A identificação do cartão pede no máximo 400 kHz, o que corresponde ao divisor 124.

### 2.1. Barramento registrado

Escrita, endereço e dado do barramento são registrados uma vez dentro do periférico, e o ciclo seguinte aplica as escritas em `CMD`, em `CONTROL.ABORT`, em `STATUS`, em `ERROR` e em `DATA`. As leituras de `STATUS`, `ERROR`, `CMD` e a saída de interrupção já incluem o efeito dessa escrita pendente, então o software enxerga o mesmo que enxergaria sem o registro: uma leitura de `STATUS` logo depois de escrever `CMD` já mostra `CMD_BUSY`. As leituras não ganham ciclo de espera, e `ARG`, `CONTROL`, `DIVIDER`, `TIMEOUT` e `PTR` seguem a escrita no mesmo ciclo.

| Efeito | Diferença |
| :--- | :--- |
| Início do quadro em `SD_CMD` depois da escrita em `CMD` | 1 ciclo do núcleo a mais, invisível diante de um `SD_CLK` de 40 ns ou mais |
| Fim de comando, fim de dados e erros | Aparecem 1 ciclo depois, de forma coerente entre si |
| Escrita em `DATA` | Chega ao buffer 1 ciclo depois, e a leitura do mesmo endereço no ciclo seguinte recebe o dado novo |

## 3. Preparar o cartão

### 3.1. Cartão cru

A imagem tem três regiões, todas em setores de 512 bytes e em little endian.

| Região | Setor | Conteúdo |
| :--- | ---: | :--- |
| Cabeçalho | 2048 | Magia `DOOM` e `SD01`, versão, sinalizadores, quantidade de WADs, setores do índice, setor, tamanho e CRC-32 do payload, endereço de destino na SDRAM e CRC-32 do índice; os últimos 4 bytes do setor são o CRC-32 dos 508 anteriores |
| Índice | 2049 em diante | 128 bytes por WAD (nome, título, subtítulo, endereço, tamanho e tipo), 4 entradas por setor |
| Payload | Primeiro múltiplo de 8 depois do índice (2056 com 24 WADs) | O `wads.bin` sem alteração |

O `scripts/sdwrite.py` do DOOM monta a imagem e a grava, sempre com Python pelo `uv`.

```bash
uv run --no-project scripts/sdwrite.py --dry-run --target /dev/mmcblk0
uv run --no-project scripts/sdwrite.py --target /dev/mmcblk0
```

| Cuidado | Motivo |
| :--- | :--- |
| Nomear o dispositivo na linha de comando | O script não adivinha o disco |
| Só disco inteiro de cartão SD, MMC ou removível, sem partição montada | Recusa outro tipo de dispositivo |
| Confirmar o nome digitando ou com `--confirm` | Evita apagar o disco errado |
| Arquivo de imagem como alvo | Dispensa as travas de disco, para testar sem cartão |

A gravação apaga a tabela de partições, e o cartão deixa de ser um FAT32.

### 3.2. Cartão FAT32

O cartão é comum, sem script. O guia completo é o `docs/pt-br/CARTAO-FATFS.md` do DOOM, e o resumo é este.

1. Formatar em FAT32, com cluster de 32 KB ou maior, que deixa a FAT curta. No Linux, `sudo mkfs.vfat -F 32 -s 64 -n DOOM /dev/sdX1`. No Windows, tamanho da unidade de alocação 32 KB, ou `format fs=fat32 unit=32768 quick` no `diskpart` para cartões acima de 32 GB. Formatar apaga o cartão inteiro.
2. Copiar para a raiz `DOOM.WAD`, `DOOM2.WAD`, `PLUTONIA.WAD` e `TNT.WAD`, com nomes no formato 8.3.
3. Para o Master Levels, criar a pasta `MASTER` e copiar as 20 fases e o `DOOM2.MAP`. Ele só aparece no menu junto do `DOOM2.WAD`.
4. Ejetar o cartão pelo sistema.

O menu mostra só o que achar no cartão.

## 4. Camadas de software

### 4.1. Driver do sd_native

O mesmo driver (`port/doom_sd.c` do DOOM) serve às duas formas. Ele inicializa o cartão, lê setores com CMD17 por polling, repete até 3 vezes uma leitura que falha e guarda 8 setores numa pequena cache para leituras que não cobrem um setor inteiro. Não usa interrupção: os bits de habilitação de `CONTROL` ficam em 0.

### 4.2. Forma crua

O software lê o cabeçalho do setor 2048, confere o CRC-32 e o índice e calcula o setor de cada WAD pelo deslocamento do payload. Uma leitura de dados é um laço de CMD17 sobre os setores do intervalo, sem passar por tabela de alocação.

### 4.3. Forma FatFs

O [FatFs](http://elm-chan.org/fsw/ff/) do ChaN roda sobre uma camada de disco fina (`port/doom_diskio.c`) que liga a inicialização do disco e a leitura de setores ao driver do sd_native. A configuração (`port/ffconf.h`) é a menor que o jogo precisa.

| Opção | Valor | Efeito |
| :--- | :--- | :--- |
| `FF_FS_READONLY` | 1 | Sem escrita; o cartão nunca é alterado |
| `FF_USE_LFN` | 0 | Só nomes 8.3 |
| `FF_USE_FASTSEEK` | 1 | O salto dentro de um arquivo grande não percorre a FAT |
| `FF_USE_MKFS` | 0 | Sem formatação pelo SoC |
| `FF_FS_EXFAT` | 0 | Só FAT12, FAT16 e FAT32; o cartão é FAT32 |
| `FF_MULTI_PARTITION` | 0 | Uma unidade lógica: a primeira partição do MBR, ou o volume sem MBR |
| `FF_MIN_SS` e `FF_MAX_SS` | 512 | Setor de 512 bytes |

A camada de disco entrega a leitura direto ao destino quando ele está alinhado a 4 bytes, e passa por um buffer de um setor quando não está, porque o buffer do controlador é lido em palavras de 32 bits. A capacidade do cartão vem do CMD9, que só o build FatFs executa, uma vez na inicialização.

## 5. Sequência de inicialização e leitura de um bloco

O driver segue a sequência da especificação para SDHC e SDXC.

| Passo | Ação | Verificação |
| ---: | :--- | :--- |
| 1 | Aborta qualquer operação, zera `CONTROL` e escreve em `DIVIDER` o divisor de identificação | Divisor 124, 400 kHz |
| 2 | Liga `CLK_ENABLE` por 2 ms e o desliga | Pelo menos 74 clocks com `CMD` em 1 |
| 3 | CMD0, sem resposta | Sem `ERROR` |
| 4 | CMD8 com `0x000001AA`, resposta curta | Os 12 bits baixos de `RESP0` valem `0x1AA`; sem resposta, não há cartão; diferente, cartão não suportado |
| 5 | Repete CMD55 e ACMD41 com `0x40FF8000` (resposta sem CRC) a cada 5 ms, por até 1,2 s | Bit 31 de `RESP0` em 1 |
| 6 | Confere o bit 30 de `RESP0`, o CCS | Em 0 é cartão SDSC, recusado |
| 7 | CMD2 (resposta longa) e CMD3 | RCA nos bits 31 a 16 de `RESP0` |
| 8 | Só no FatFs: CMD9 com o RCA (resposta longa); a forma crua pula este passo | Se o CSD é da versão 2, a capacidade é $(C\_SIZE + 1) \cdot 1024$ setores; se falhar, a capacidade fica 0 e a inicialização segue |
| 9 | CMD7 com o RCA e `WAIT_BUSY` | Cartão no estado de transferência |
| 10 | CMD55 e ACMD6 com argumento 2, depois `WIDE_BUS` em `CONTROL` | Quatro linhas de dados |
| 11 | `DIVIDER` em 1 e `TIMEOUT` em 5000000 | 25 MHz, prazo de 0,2 s |

A leitura de um setor é um comando só: escrever o número do setor em `ARG` (o cartão SDHC endereça por setor, não por byte), escrever CMD17 com resposta curta e `DATA_EN` em `CMD`, esperar `CMD_DONE` e `DATA_DONE` em `STATUS`, limpar as marcas, conferir `ERROR`, apontar `PTR` para 0 e ler 128 palavras de `DATA`. Durante `DATA_BUSY` o software não acessa `DATA`, porque o controle de dados é dono do buffer.

```c
#include <stdbool.h>
#include <stdint.h>

#define SD_BASE ((volatile uint32_t *)0x80008000u)

enum { ARG = 0, CMD = 1, STATUS = 6, ERROR = 7, DATA = 11, PTR = 12 };
enum { CMD_DONE = 1u << 2, DATA_DONE = 1u << 3 };
enum { CMD17 = 17u, RSP_R1 = 1u << 6, DATA_EN = 1u << 9 };

/* Lê o setor de 512 bytes em words, com o cartão já inicializado. */
bool sd_read_sector(uint32_t sector, uint32_t words[static 128])
{
    SD_BASE[ARG] = sector;
    SD_BASE[CMD] = CMD17 | RSP_R1 | DATA_EN;
    while ((SD_BASE[STATUS] & (CMD_DONE | DATA_DONE)) != (CMD_DONE | DATA_DONE)) {
    }
    SD_BASE[STATUS] = CMD_DONE | DATA_DONE;
    uint32_t errors = SD_BASE[ERROR];
    SD_BASE[ERROR] = errors;
    if (errors != 0u) {
        return false;
    }
    SD_BASE[PTR] = 0;
    for (uint32_t i = 0; i < 128u; i++) {
        words[i] = SD_BASE[DATA];
    }
    return true;
}
```

Uma leitura real limita a espera, aborta o comando em `CONTROL` quando o prazo acaba e repete a leitura. O exemplo completo da inicialização, com as escritas, está em [sd_native.md](sd_native.md), seção 6.3.

## 6. Habilitar na plataforma DOOM

O periférico entra no `platform.yaml` da plataforma, em `peripherals`, com o tipo `sd_native` e o endereço. O clock do periférico é o do núcleo (`clocks.core`, 100 MHz), e a linha de interrupção que o mapa lhe atribui fica sem uso, porque o driver faz polling.

```yaml
SD:
  kind: sd_native
  base: 0x80008000
```

Depois de editar o arquivo, o `riscv-tools generate-memory-map` regenera o mapa e o topo, e o `memory_map.h` passa a trazer a base do SD. O driver usa `0x80008000` quando a constante não existe. As variáveis de build do DOOM que escolhem a forma são `SD=demand ONDEMAND=1` (as WADs ficam só no cartão) e `SDFS=raw` ou `SDFS=fatfs`.

## 7. Limitações

| Limitação | Detalhe |
| :--- | :--- |
| Só SDHC e SDXC | O driver confere o bit CCS do OCR e recusa cartão SDSC, que endereça por byte |
| Só leitura | O controlador sabe escrever blocos (CMD24, testado em simulação), mas o driver da plataforma, o FatFs e a camada de disco só leem |
| Capacidade (CMD9) | Lida só na forma FatFs, que a usa; a forma crua inicializa sem CMD9. Se o CMD9 falhar, a capacidade fica 0 e a inicialização segue |
| Nomes longos | O FatFs roda sem nomes longos; um cartão FAT32 que misture nomes longos e curtos não foi testado |
| Interrupção | O driver faz polling; o caminho por interrupção do controlador não é exercido pela plataforma |
| Validação em cartão real | O FatFs foi testado na placa com um cartão FAT32 de 30 GB, formatado com cluster de 32 KB, e os 5 jogos (DOOM, DOOM II, Plutonia, TNT e Master Levels) |

---

Copyright 2026 Insper. Licenciado sob a [Apache License, Version 2.0](../../../LICENSE).
