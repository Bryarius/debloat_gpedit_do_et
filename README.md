# Debloat GPEdit — Otimização do Windows 10/11
<img width="480" height="269" alt="et_4k_hdr" src="https://github.com/user-attachments/assets/f6b2057a-0caf-42f3-a9a7-3736fa8779c3" />
Script PowerShell que aplica configurações de política de grupo via registro do Windows,
baseado no método apresentado por **Enzo Túlio** (canal [1155 do ET](https://www.youtube.com/@1155doET))
no vídeo ["SÓ CONSIGO USAR O WINDOWS 11 ASSIM!"](https://www.youtube.com/watch?v=kQM-iv7TQz0&t=2258s).

## O que faz

O script realiza alterações no registro para desativar recursos desnecessários do Windows 10/11,
reduzindo consumo de memória e processos em segundo plano. As alterações são equivalentes às
políticas de grupo (GPEdit) aplicadas manualmente no vídeo.

## Requisitos

- Windows 10 ou 11
- PowerShell 5.1 ou superior
- **Executar como Administrador**

## Como usar

```powershell
irm https://raw.githubusercontent.com/Bryarius/debloat_gpedit_do_et/main/debloat.ps1 | iex   
