# Debloat GPEdit — Otimização do Windows 10/11

<img width="754" height="761" alt="rlk_do_et" src="https://github.com/user-attachments/assets/cc50c913-2a0e-4409-a334-782b002955dd" />


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
