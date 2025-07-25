/**
 * Clean Node Interactions System
 * 
 * Professional hover and selection effects for Plotly DAG visualization
 * Inspired by Notion, Linear, and other modern UIs
 */

// Lazy initialize Clean Interactions based on glow-settings store
window.addEventListener("DOMContentLoaded", () => {
    const glowSettingsStore = document.querySelector('#glow-settings');
    const glowData = glowSettingsStore?.dataset?.store || "{}";
    const parsedSettings = JSON.parse(glowData);

    if (parsedSettings.enabled) {
        // Initialize the clean interactions system
        window.nodeInteractions = {
            activeInteractions: new Map(),
            interactionPool: [],
            hoverTimeouts: new Map(),
            lastHoveredNode: null,
            selectedNodes: new Set(),
            isProcessing: false,
            pendingHover: null,
            rafId: null,

            /**
             * Create a clean hover interaction for a node
             * @param {string} nodeId - The ID of the node to highlight
             */
            async createHoverInteraction(nodeId) {
                if (this.isProcessing) {
                    this.pendingHover = { nodeId };
                    return;
                }

                this.isProcessing = true;

                try {
                    await this._handleNodeTransition(nodeId);
                    this.lastHoveredNode = nodeId;
                    this.clearHoverTimeout(nodeId);

                    const graphDiv = document.getElementById('dependency-graph');
                    if (!graphDiv) return;

                    this.removeInteraction(nodeId);
                    const actualNodePosition = await this.findActualNodePosition(nodeId);
                    if (!actualNodePosition) return;

                    const interactionDiv = this.getInteractionFromPool();
                    this.setupInteractionElement(interactionDiv, nodeId, actualNodePosition);

                    graphDiv.appendChild(interactionDiv);
                    this.activeInteractions.set(nodeId, interactionDiv);

                    // Smooth activation
                    requestAnimationFrame(() => {
                        if (this.lastHoveredNode === nodeId) {
                            setTimeout(() => {
                                if (this.lastHoveredNode === nodeId) {
                                    interactionDiv.classList.add('hovered');
                                }
                            }, 10);
                        }
                    });
                } finally {
                    this.isProcessing = false;

                    if (this.pendingHover) {
                        const pending = this.pendingHover;
                        this.pendingHover = null;
                        this.rafId = requestAnimationFrame(() => {
                            this.createHoverInteraction(pending.nodeId);
                        });
                    }
                }
            },

            /**
             * Create a selection interaction with optional pulse effect
             * @param {string} nodeId - The ID of the node to select
             * @param {boolean} showPulse - Whether to show a pulse animation
             */
            createSelectionInteraction(nodeId, showPulse = true) {
                this.selectedNodes.add(nodeId);

                const existingInteraction = this.activeInteractions.get(nodeId);
                if (existingInteraction) {
                    existingInteraction.classList.add('selected');
                    if (showPulse) {
                        existingInteraction.classList.add('selection-pulse');
                        setTimeout(() => {
                            existingInteraction.classList.remove('selection-pulse');
                        }, 300);
                    }
                } else {
                    this._createSelectionInteractionAsync(nodeId, showPulse);
                }
            },

            /**
             * Clear selection state for one or all nodes
             * @param {string|null} nodeId - Specific node ID or null for all
             */
            clearSelection(nodeId = null) {
                if (nodeId) {
                    this.selectedNodes.delete(nodeId);
                    const interaction = this.activeInteractions.get(nodeId);
                    if (interaction) {
                        interaction.classList.remove('selected', 'selection-pulse');
                    }
                } else {
                    this.selectedNodes.clear();
                    this.activeInteractions.forEach((interaction) => {
                        interaction.classList.remove('selected', 'selection-pulse');
                    });
                }
            },

            /**
             * End hover interaction with clean fade
             * @param {string} nodeId - The ID of the node
             * @param {number} delay - Delay before ending hover
             */
            endHoverInteraction(nodeId, delay = 50) {
                this.clearHoverTimeout(nodeId);

                const timeout = setTimeout(() => {
                    const interactionDiv = this.activeInteractions.get(nodeId);
                    if (interactionDiv && interactionDiv.classList.contains('hovered')) {
                        if (!this.selectedNodes.has(nodeId)) {
                            interactionDiv.classList.remove('hovered');
                            interactionDiv.classList.add('fading-out');
                            setTimeout(() => {
                                this.removeInteraction(nodeId);
                            }, 120);
                        } else {
                            interactionDiv.classList.remove('hovered');
                        }
                    }
                }, delay);

                this.hoverTimeouts.set(nodeId, timeout);
            },

            /**
             * Find the actual DOM position of a rendered node
             * @param {string} nodeId - The ID of the node to find
             * @returns {Object|null} Position object or null if not found
             */
            async findActualNodePosition(nodeId) {
                const graphDiv = document.getElementById('dependency-graph');
                await new Promise(resolve => requestAnimationFrame(resolve));

                console.log("🔍 Searching for node:", nodeId);

                // Get the actual domain name from node dimensions
                const nodeData = window.nodeDimensions?.[nodeId];
                const domainName = nodeData?.label;

                if (!domainName) {
                    console.warn("❌ No domain name found for:", nodeId);
                    return null;
                }

                console.log("🎯 Looking for domain name:", domainName);

                // Strategy 1: Find the rect element with sibling text containing domain name
                const allGroups = graphDiv.querySelectorAll('g.scatterlayer g.trace g.points g.point');
                for (let pointGroup of allGroups) {
                    const textEl = pointGroup.querySelector('text');
                    const rectEl = pointGroup.querySelector('rect');

                    if (textEl && rectEl) {
                        const textContent = textEl.textContent?.trim();
                        if (textContent === domainName || textContent?.includes(domainName)) {
                            console.log("✅ Found node rect by exact structure:", domainName);
                            return this.getElementPosition(rectEl, nodeId);
                        }
                    }
                }

                // Strategy 2: Find rect elements near text with domain name
                const textElements = graphDiv.querySelectorAll('text');
                for (let textEl of textElements) {
                    const textContent = textEl.textContent?.trim();
                    if (textContent === domainName || (textContent && domainName.includes(textContent))) {
                        const parentGroup = textEl.closest('g');
                        if (parentGroup) {
                            const rect = parentGroup.querySelector('rect');
                            if (rect) {
                                console.log("✅ Found node rect via parent group:", domainName);
                                return this.getElementPosition(rect, nodeId);
                            }
                        }
                    }
                }

                // Strategy 3: Handle multi-line text (wrapped labels)
                const tspanElements = graphDiv.querySelectorAll('text tspan');
                for (let tspan of tspanElements) {
                    if (tspan.textContent && domainName.includes(tspan.textContent.trim())) {
                        const textEl = tspan.closest('text');
                        const parentGroup = textEl?.closest('g');
                        if (parentGroup) {
                            const rect = parentGroup.querySelector('rect');
                            if (rect) {
                                console.log("✅ Found node rect via tspan:", domainName);
                                return this.getElementPosition(rect, nodeId);
                            }
                        }
                    }
                }

                // Strategy 4: Fallback - search by node ID
                for (let textEl of textElements) {
                    if (textEl.textContent && textEl.textContent.includes(nodeId)) {
                        const parentGroup = textEl.closest('g');
                        if (parentGroup) {
                            const rect = parentGroup.querySelector('rect');
                            if (rect) {
                                console.log("✅ Found node rect by ID fallback:", nodeId);
                                return this.getElementPosition(rect, nodeId);
                            }
                        }
                    }
                }

                console.warn("❌ Could not find node element for:", nodeId, "with domain name:", domainName);
                return null;
            },

            /**
             * Get element position relative to graph container
             * @param {Element} element - The DOM element
             * @param {string} nodeId - The node ID for logging
             * @returns {Object} Position object
             */
            getElementPosition(element, nodeId) {
                try {
                    const graphDiv = document.getElementById('dependency-graph');
                    const elementRect = element.getBoundingClientRect();
                    const containerRect = graphDiv.getBoundingClientRect();

                    // Calculate position relative to graph container
                    const position = {
                        left: elementRect.left - containerRect.left,
                        top: elementRect.top - containerRect.top,
                        width: elementRect.width,
                        height: elementRect.height
                    };

                    // Add small padding for better visual coverage
                    const padding = 2;
                    position.left -= padding;
                    position.top -= padding;
                    position.width += padding * 2;
                    position.height += padding * 2;

                    console.log("📐 Element position for", nodeId, ":", position);

                    return position;
                } catch (error) {
                    console.error("Error getting element position:", error);
                    return null;
                }
            },

            /**
             * Setup interaction element with proper styling and positioning
             * @param {Element} interactionDiv - The interaction div element
             * @param {string} nodeId - The node ID
             * @param {Object} nodePosition - Position object
             */
            setupInteractionElement(interactionDiv, nodeId, nodePosition) {
                interactionDiv.dataset.nodeId = nodeId;
                interactionDiv.className = 'node-interaction';

                const nodeData = window.nodeDimensions?.[nodeId];
                if (nodeData) {
                    interactionDiv.dataset.tier = nodeData.tier;
                    if (nodePosition.width < 60) {
                        interactionDiv.classList.add('small-node');
                    } else if (nodePosition.width > 120) {
                        interactionDiv.classList.add('large-node');
                    }
                }

                Object.assign(interactionDiv.style, {
                    left: `${nodePosition.left}px`,
                    top: `${nodePosition.top}px`,
                    width: `${nodePosition.width}px`,
                    height: `${nodePosition.height}px`,
                    position: 'absolute',
                    zIndex: '1000'
                });
            },

            /**
             * Get an interaction div from the object pool
             * @returns {Element} Interaction div element
             */
            getInteractionFromPool() {
                if (this.interactionPool.length > 0) {
                    const div = this.interactionPool.pop();
                    div.className = 'node-interaction';
                    return div;
                }
                const div = document.createElement('div');
                div.className = 'node-interaction';
                return div;
            },

            /**
             * Handle smooth transitions between nodes
             * @param {string} newNodeId - The new node being hovered
             */
            async _handleNodeTransition(newNodeId) {
                if (this.lastHoveredNode && this.lastHoveredNode !== newNodeId) {
                    this.previousHoveredNode = this.lastHoveredNode;
                    const prevInteraction = this.activeInteractions.get(this.previousHoveredNode);
                    if (prevInteraction && prevInteraction.classList.contains('hovered')) {
                        prevInteraction.classList.remove('hovered');
                        if (!this.selectedNodes.has(this.previousHoveredNode)) {
                            prevInteraction.classList.add('fading-out');
                            setTimeout(() => {
                                this.removeInteraction(this.previousHoveredNode);
                            }, 120);
                        }
                    }
                }
            },

            /**
             * Create selection interaction asynchronously
             * @param {string} nodeId - The node ID
             * @param {boolean} showPulse - Whether to show pulse animation
             */
            async _createSelectionInteractionAsync(nodeId, showPulse) {
                const graphDiv = document.getElementById('dependency-graph');
                if (!graphDiv) return;

                const actualNodePosition = await this.findActualNodePosition(nodeId);
                if (!actualNodePosition) return;

                const interactionDiv = this.getInteractionFromPool();
                this.setupInteractionElement(interactionDiv, nodeId, actualNodePosition);

                graphDiv.appendChild(interactionDiv);
                this.activeInteractions.set(nodeId, interactionDiv);

                requestAnimationFrame(() => {
                    interactionDiv.classList.add('selected');
                    if (showPulse) {
                        interactionDiv.classList.add('selection-pulse');
                        setTimeout(() => {
                            interactionDiv.classList.remove('selection-pulse');
                        }, 300);
                    }
                });
            },

            /**
             * Clean up all interactions
             */
            cleanup() {
                if (this.rafId) {
                    cancelAnimationFrame(this.rafId);
                    this.rafId = null;
                }

                this.isProcessing = false;
                this.pendingHover = null;

                if (this.lastHoveredNode) {
                    this.endHoverInteraction(this.lastHoveredNode, 0);
                    this.lastHoveredNode = null;
                }

                setTimeout(() => {
                    this.activeInteractions.forEach((interaction) => {
                        if (interaction.parentNode) {
                            interaction.parentNode.removeChild(interaction);
                        }
                        this._resetInteractionElement(interaction);
                        if (this.interactionPool.length < 10) {
                            this.interactionPool.push(interaction);
                        }
                    });

                    this.hoverTimeouts.forEach(timeout => clearTimeout(timeout));
                    this.activeInteractions.clear();
                    this.hoverTimeouts.clear();
                    this.selectedNodes.clear();
                }, 150);
            },

            /**
             * Remove a specific interaction
             * @param {string} nodeId - The node ID
             */
            removeInteraction(nodeId) {
                const interactionDiv = this.activeInteractions.get(nodeId);
                if (interactionDiv && interactionDiv.parentNode) {
                    interactionDiv.parentNode.removeChild(interactionDiv);
                    this._resetInteractionElement(interactionDiv);
                    if (this.interactionPool.length < 10) {
                        this.interactionPool.push(interactionDiv);
                    }
                }
                this.activeInteractions.delete(nodeId);
                this.clearHoverTimeout(nodeId);
            },

            /**
             * Reset interaction element to default state
             * @param {Element} element - The element to reset
             */
            _resetInteractionElement(element) {
                element.className = 'node-interaction';
                element.style.cssText = '';
                delete element.dataset.nodeId;
                delete element.dataset.tier;
            },

            /**
             * Clear hover timeout for a node
             * @param {string} nodeId - The node ID
             */
            clearHoverTimeout(nodeId) {
                const timeout = this.hoverTimeouts.get(nodeId);
                if (timeout) {
                    clearTimeout(timeout);
                    this.hoverTimeouts.delete(nodeId);
                }
            },

            // Backward compatibility methods
            createHoverGlowDirect(nodeId) {
                return this.createHoverInteraction(nodeId);
            },

            endHoverGlow(nodeId, delay) {
                return this.endHoverInteraction(nodeId, delay);
            },

            setSelected(nodeId, selected = true) {
                if (selected) {
                    this.createSelectionInteraction(nodeId, false);
                } else {
                    this.clearSelection(nodeId);
                }
            }
        };

        // For legacy compatibility
        window.glowEffects = window.nodeInteractions;

        console.log("✨ Clean Interactions ENABLED");

        // Re-run original DOM ready logic
        console.log('🎯 Clean interactions system loaded');
        console.log('Node dimensions:', Object.keys(window.nodeDimensions || {}).length, 'nodes');

        window.addEventListener('beforeunload', function () {
            if (window.nodeInteractions) {
                window.nodeInteractions.cleanup();
            }
        });

        console.log(`🎯 CLEAN INTERACTIONS SYSTEM READY

API Methods:
    window.nodeInteractions.createHoverInteraction(nodeId)
    window.nodeInteractions.createSelectionInteraction(nodeId, showPulse)
    window.nodeInteractions.clearSelection()
    window.nodeInteractions.endHoverInteraction(nodeId, delay)

Features:
✨ Subtle hover effects
🎯 Clean selection states
⚡ High performance
♿ Accessible

The system automatically finds and highlights nodes in your Plotly graph!
        `);
    } else {
        console.log("💤 Clean Interactions DISABLED");
    }
});