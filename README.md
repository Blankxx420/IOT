# Inception of Things - 42 Project

Bienvenue sur mon dépôt du projet **Inception-of-Things (IoT)**. Ce projet est une immersion dans le monde de l'administration système, de l'infrastructure en tant que code (IaC), de Kubernetes et de l'automatisation CI/CD.

## Table des Matières
- [Inception of Things - 42 Project](#inception-of-things---42-project)
  - [Table des Matières](#table-des-matières)
  - [Partie 1 \& 2 : Infrastructure avec Vagrant \& K3s](#partie-1--2--infrastructure-avec-vagrant--k3s)
    - [Fonctionnement :](#fonctionnement-)
  - [Partie 3 : K3d et GitOps (ArgoCD)](#partie-3--k3d-et-gitops-argocd)
    - [Objectifs :](#objectifs-)
  - [Bonus : GitLab dans le cluster](#bonus--gitlab-dans-le-cluster)
    - [Étapes clés :](#étapes-clés-)
    - [Prérequis](#prérequis)

---

## Partie 1 & 2 : Infrastructure avec Vagrant & K3s
Dans cette partie, nous automatisons la création d'un cluster Kubernetes multi-nœuds (1 serveur, 1 worker) utilisant des machines virtuelles gérées par Vagrant.

### Fonctionnement :
* **Vagrantfile :** Définit les deux machines virtuelles (`k3s-server`, `k3s-worker`) avec la configuration réseau appropriée (IP privées, bridge ou NAT).
* **Provisioning :** Utilisation de scripts shell pour installer automatiquement `K3s` sur le serveur et joindre le worker au cluster via le token généré.
* **Accès :** Vous pouvez interagir avec le cluster directement depuis le serveur ou en exportant le `kubeconfig`.

```bash
# Pour lancer le cluster
vagrant up


# Pour se connecter au serveur
vagrant ssh k3s-server
```

## Partie 3 : K3d et GitOps (ArgoCD)
La partie 3 se concentre sur Kubernetes "léger" (K3d) et l'implémentation d'une stratégie GitOps.

### Objectifs :
* **K3d :** Création d'un cluster Kubernetes encapsulé dans Docker.

* **ArgoCD :** Installation et configuration d'ArgoCD pour gérer le déploiement de vos applications de manière déclarative.

* **Workflow :** Les changements de configuration dans votre dépôt Git sont automatiquement synchronisés avec l'état souhaité dans le cluster par ArgoCD.

Lancement du cluster K3d :
```Bash
k3d cluster create iot-cluster --agents 1 -p "80:80@loadbalancer" -p "443:443@loadbalancer" -p "8080:8080@loadbalancer"
```

## Bonus : GitLab dans le cluster
L'objectif est d'héberger votre propre instance de GitLab directement dans votre cluster Kubernetes pour centraliser votre code et vos pipelines CI/CD.

### Étapes clés :
* **Helm :** Utilisation de Helm pour déployer GitLab.

* **Configuration :** Mise en place d'un Ingress pour accéder à l'interface GitLab via un nom de domaine local (ex: gitlab.local).

* **Pipeline :** Création d'un Runner GitLab pour exécuter des tâches CI/CD qui interagissent avec votre cluster.

* **Note :** GitLab est très gourmand en ressources. Assurez-vous d'avoir au moins 8 Go de RAM disponible.

### Prérequis
Pour travailler sur ce projet, assurez-vous d'avoir installé les outils suivants sur votre machine hôte :

VirtualBox & Vagrant

Docker

K3d

Kubectl

Helm

Make

*Ce projet fait partie du cursus de l'École 42.*